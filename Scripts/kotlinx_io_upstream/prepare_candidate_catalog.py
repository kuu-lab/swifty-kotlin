#!/usr/bin/env python3
"""Prepare the pinned Native catalog with original factory classes and hooks.

This preserves original sources and assertions. Preparation does not prove that
the candidate compiles or passes, and does not export paired observations.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

from run_candidate_subset import IDENTIFIER, PREFIX
from run_jvm_reference import sha256, verify_file


def prepare_catalog(upstream: Path, catalog: list[dict], lock: dict,
                    suites: list[str] | None, output: Path, target: str,
                    declarations: dict) -> list[dict]:
    if target not in {"linux", "macos"}:
        raise ValueError("catalog target must be linux or macos")
    if (declarations["schema_version"] != 1 or declarations["upstream_commit"] != lock["commit"]
            or declarations["native_execution_catalog_sha256"] != lock["native_execution_catalog_sha256"]):
        raise ValueError("candidate declaration index does not match pinned catalog")
    eligible = [row for row in catalog if row["source_set"] == "common" or target == "macos"]
    classes = {row["concrete_class"]: row for row in declarations["classes"]}
    if len(classes) != len(declarations["classes"]):
        raise ValueError("duplicate concrete class locator")
    if set(classes) != {row["concrete_class"] for row in catalog}:
        raise ValueError("class locators must cover the complete pinned catalog")
    selected = set(suites) if suites else {row["concrete_class"] for row in eligible}
    if suites is not None and (not suites or len(selected) != len(suites)):
        raise ValueError("suite selection must be nonempty and unique")
    if not selected <= {row["concrete_class"] for row in eligible}:
        raise ValueError("selected class is absent from the target catalog")
    rows = [row for row in eligible if row["concrete_class"] in selected]
    identifiers = [row["execution_id"] for row in rows]
    if len(set(identifiers)) != len(rows):
        raise ValueError("duplicate locked execution ID")

    records = {row["path"]: row for row in lock["upstream_files"]}
    paths = sorted(row["path"] for row in lock["upstream_files"]
                   if "Windows" not in row["path"] and ("/common/test/" in row["path"]
                   or "/native/test/" in row["path"] or target == "macos" and "/apple/test/" in row["path"]))
    if paths != sorted(declarations["source_closures"][target]) or len(set(paths)) != len(paths):
        raise ValueError("original source closure must match the reference lane")
    texts = {}
    sources = []
    for path in paths:
        verify_file(upstream / path, records[path])
        raw = (upstream / path).read_bytes()
        texts[path] = raw.decode("utf-8")
        port = output / "ports" / path
        port.parent.mkdir(parents=True, exist_ok=True)
        port.write_bytes(PREFIX + raw)
        sources.append({"source_path": path, "source_sha256": records[path]["sha256"],
                        "source_git_blob_sha": records[path]["git_blob_sha"],
                        "port_path": str(port), "port_sha256": sha256(port),
                        "prefix_bytes": len(PREFIX),
                        "original_bytes_preserved_as_suffix": port.read_bytes()[len(PREFIX):] == raw})

    for suite in selected:
        if not all(IDENTIFIER.fullmatch(part) for part in suite.split(".")):
            raise ValueError("unsupported concrete class identifier")
        locator = classes[suite]
        path = locator["source_path"]
        if path not in texts or (locator["source_sha256"] != records[path]["sha256"]
                                or locator["git_blob_sha"] != records[path]["git_blob_sha"]):
            raise ValueError("concrete class source does not match lock")
        lines = texts[path].splitlines()
        line = locator["class_declaration_line"] - 1
        if line < 0 or line >= len(lines) or lines[line].strip() != locator["declaration"]:
            raise ValueError("original concrete class declaration changed")
        hooks = locator["hook_methods"]
        expected_hooks = ["cleanup"] if suite == "kotlinx.io.files.SmokeFileTest" else []
        if hooks != expected_hooks:
            raise ValueError("unreviewed lifecycle hook")
        if hooks and not re.search(r"@AfterTest\s+fun\s+cleanup\s*\(\s*\)", texts[path]):
            raise ValueError("original cleanup hook is absent")
        actual = [row for row in catalog if row["concrete_class"] == suite]
        if len(actual) != locator["execution_count"] or {row["declaring_class"] for row in actual} != set(locator["declaring_classes"]):
            raise ValueError("class factory expansion differs from declaration audit")
    for row in rows:
        suite, method, path = row["concrete_class"], row["method_name"], row["upstream_path"]
        if row["parameter_types"] or not IDENTIFIER.fullmatch(method):
            raise ValueError("unreviewed parameterized method")
        if row["execution_id"] != suite + "." + method or row["upstream_id"] != path + "#" + method:
            raise ValueError("source function / execution ID mismatch")
        if (path not in texts or row["git_blob_sha"] != records[path]["git_blob_sha"]
                or not re.search(r"\bfun\s+" + re.escape(method) + r"\s*\(\s*\)", texts[path])):
            raise ValueError("locked method is not an original parameterless declaration")

    token = "KIO_" + hashlib.sha256(json.dumps(identifiers).encode()).hexdigest()[:24]
    driver = ["fun main() {"]
    for row in rows:
        suite, method, identifier = row["concrete_class"], row["method_name"], row["execution_id"]
        driver += [f'    println("{token} BEGIN {identifier}")', "    try {"]
        if classes[suite]["hook_methods"]:
            driver += [f"        val instance by lazy {{ {suite}() }}", "        try {",
                       f"            instance.{method}()", "        } finally {",
                       "            instance.cleanup()", "        }"]
        else:
            driver += [f"        {suite}().{method}()"]
        driver += [f'        println("{token} PASS {identifier}")', "    } catch (failure: Throwable) {",
                   f'        println("{token} FAIL {identifier}")',
                   f'        println("{token} EXCEPTION " + failure::class.qualifiedName)', "    }"]
    driver += ["}", ""]
    driver_path = output / "CombinedDriver.kt"
    driver_path.write_text("\n".join(driver))
    return [{"suite": "native-catalog-" + target, "target": target,
             "source_ports": [row["port_path"] for row in sources], "original_sources": sources,
             "driver_path": str(driver_path), "driver_sha256": sha256(driver_path),
             "execution_ids": identifiers, "source_function_ids": sorted({row["upstream_id"] for row in rows}),
             "event_token": token, "assertions_parameters_constructors_changed": False,
             "constructor_policy": "fresh original concrete class instance per execution",
             "lifecycle_policy": declarations["lifecycle_policy"]}]
