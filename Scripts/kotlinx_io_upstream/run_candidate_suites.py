#!/usr/bin/env python3
"""Run locked original suites together, from source or a separate test library.

Original assertions and constructors are preserved. The audited Native catalog
driver supports its concrete factories and cleanup hook; paired PASS is zero.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import platform
import subprocess
import sys

from run_candidate_subset import parse_events, prepare_port, tree_hash
from prepare_candidate_catalog import prepare_catalog
from run_jvm_reference import HERE, execute, sha256, verify_file


MAX_EXPLICIT_SELECTIONS_PER_KIND = 10


def canonical_sha256(value: object) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def target_catalog_rows(catalog: list[dict], target: str | None) -> list[dict]:
    if target is None:
        return list(catalog)
    if target not in {"linux", "macos"}:
        raise ValueError("catalog target must be linux or macos")
    return [row for row in catalog if row["source_set"] == "common" or target == "macos"]


def select_catalog_rows(catalog: list[dict], suites: list[str] | None, target: str | None,
                        source_function_ids: list[str] | None = None,
                        execution_ids: list[str] | None = None) -> list[dict]:
    source_ids = list(source_function_ids or [])
    exact_ids = list(execution_ids or [])
    requested = source_ids + exact_ids
    if len(source_ids) > MAX_EXPLICIT_SELECTIONS_PER_KIND:
        raise ValueError(f"at most {MAX_EXPLICIT_SELECTIONS_PER_KIND} source function IDs may be selected")
    if len(exact_ids) > MAX_EXPLICIT_SELECTIONS_PER_KIND:
        raise ValueError(f"at most {MAX_EXPLICIT_SELECTIONS_PER_KIND} concrete execution IDs may be selected")
    if any(not identifier or identifier != identifier.strip() for identifier in requested):
        raise ValueError("selected IDs must be nonempty and have no surrounding whitespace")
    if len(set(source_ids)) != len(source_ids) or len(set(exact_ids)) != len(exact_ids):
        raise ValueError("ID selection must be unique")

    eligible = target_catalog_rows(catalog, target)
    eligible_ids = [row["execution_id"] for row in eligible]
    if len(eligible_ids) != len(set(eligible_ids)):
        raise ValueError("duplicate locked execution ID")
    suite_set = set(suites) if suites is not None else None
    if suites is not None and (not suites or len(suites) != len(set(suites))):
        raise ValueError("suite selection must be nonempty and unique")
    all_suites = {row["concrete_class"] for row in eligible}
    if suite_set is not None and not suite_set <= all_suites:
        raise ValueError(f"selected suite is absent from target catalog: {sorted(suite_set - all_suites)[0]}")

    if not requested:
        selected = [row for row in eligible if suite_set is None or row["concrete_class"] in suite_set]
    else:
        selected_ids: set[str] = set()
        all_catalog_source_ids = {row.get("upstream_id") for row in catalog if row.get("upstream_id")}
        for source_id in source_ids:
            matches = [row for row in eligible if row.get("upstream_id") == source_id]
            if not matches:
                if source_id in all_catalog_source_ids:
                    raise ValueError(f"source function ID has no concrete executions for target {target}: {source_id}")
                raise ValueError(f"unknown source function ID: {source_id}")
            if suite_set is not None and any(row["concrete_class"] not in suite_set for row in matches):
                raise ValueError(f"suite selection omits factory-expanded executions for source function ID: {source_id}")
            selected_ids.update(row["execution_id"] for row in matches)
        for identifier in exact_ids:
            match = next((row for row in eligible if row["execution_id"] == identifier), None)
            if match is None:
                raise ValueError(f"unknown concrete execution ID for target {target or 'catalog'}: {identifier}")
            if suite_set is not None and match["concrete_class"] not in suite_set:
                raise ValueError(f"suite selection excludes concrete execution ID: {identifier}")
            if identifier in selected_ids:
                raise ValueError(f"duplicate execution selected by multiple IDs: {identifier}")
            selected_ids.add(identifier)
        if not selected_ids:
            raise ValueError("ID selection resolved to no concrete executions")
        selected = [row for row in eligible if row["execution_id"] in selected_ids]
        if len(selected) != len(selected_ids):
            raise ValueError("expected concrete execution is missing from the selected catalog")
    if not selected:
        raise ValueError("selection resolved to no concrete executions")
    return selected


def make_selection_manifest(catalog: list[dict], selected_rows: list[dict], target: str | None,
                            selection_mode: str, requested_source_function_ids: list[str],
                            requested_execution_ids: list[str], catalog_sha256: str,
                            source_file_sha256: dict[str, str] | None = None,
                            upstream_commit: str | None = None,
                            reference_lock_sha256: str | None = None) -> dict:
    eligible = target_catalog_rows(catalog, target)
    full_ids = [row["execution_id"] for row in eligible]
    selected_ids = [row["execution_id"] for row in selected_rows]
    records = [{key: row.get(key) for key in (
        "execution_id", "upstream_id", "concrete_class", "declaring_class", "method_name",
        "parameter_types", "upstream_path", "git_blob_sha", "source_set")}
        for row in selected_rows]
    for record in records:
        record["source_sha256"] = (source_file_sha256 or {}).get(record["upstream_path"])
    full_id_set = set(full_ids)
    selected_id_set = set(selected_ids)
    covers_full_catalog = (len(full_ids) == len(full_id_set) == len(selected_ids)
                           and selected_id_set == full_id_set)
    return {
        "schema_version": 1,
        "selection_mode": selection_mode,
        "target": target,
        "upstream_commit": upstream_commit,
        "catalog_sha256": catalog_sha256,
        "reference_lock_sha256": reference_lock_sha256,
        "catalog_execution_count": len(catalog),
        "target_catalog_execution_count": len(eligible),
        "target_catalog_execution_ids_sha256": canonical_sha256(full_ids),
        "requested_source_function_ids": requested_source_function_ids,
        "requested_execution_ids": requested_execution_ids,
        "selected_source_function_ids": sorted({row["upstream_id"] for row in selected_rows if row.get("upstream_id")}),
        "selected_concrete_classes": sorted({row["concrete_class"] for row in selected_rows}),
        "selected_execution_count": len(selected_rows),
        "selected_execution_ids": selected_ids,
        "selected_execution_records": records,
        "selected_execution_records_sha256": canonical_sha256(records),
        "covers_full_catalog": covers_full_catalog,
    }


def validate_full_catalog_artifact(selection: dict, results: list[dict], expected_ids: list[str]) -> None:
    expected = set(expected_ids)
    if len(expected) != len(expected_ids):
        raise ValueError("full-catalog expected IDs contain duplicates")
    selected_ids = selection.get("selected_execution_ids", [])
    if not isinstance(selected_ids, list):
        selected_ids = []
        problems = ["selected execution IDs are not a list"]
    else:
        problems = []
    result_ids = [row.get("execution_id") for row in results]
    result_states = [row.get("status") for row in results]
    if selection.get("target_catalog_execution_count") != len(expected):
        problems.append("target catalog count mismatch")
    if selection.get("selected_execution_count") != len(expected):
        problems.append("selected execution count mismatch")
    if not selection.get("covers_full_catalog"):
        problems.append("selection manifest is not full-catalog coverage")
    if len(selected_ids) != len(set(selected_ids)) or set(selected_ids) != expected:
        problems.append("selected execution IDs do not match full catalog")
    if len(result_ids) != len(set(result_ids)) or set(result_ids) != expected:
        problems.append("result execution IDs do not match full catalog")
    if len(results) != len(expected):
        problems.append("result count mismatch")
    if any(status != "PASS" for status in result_states):
        problems.append("one or more full-catalog executions did not pass")
    if problems:
        raise ValueError("full-catalog artifact mismatch: " + "; ".join(problems))


def prepare_suites(upstream: Path, catalog: list[dict], lock: dict,
                   suites: list[str], output: Path,
                   execution_ids: list[str] | None = None) -> list[dict]:
    if not suites or len(set(suites)) != len(suites):
        raise ValueError("suite selection must be nonempty and unique")
    if execution_ids is not None and (not execution_ids or len(execution_ids) != len(set(execution_ids))):
        raise ValueError("execution ID selection must be nonempty and unique")
    selected_ids = set(execution_ids) if execution_ids is not None else None
    ports = []
    source_paths = set()
    for index, suite in enumerate(suites):
        directory = output / f"suite-{index:03d}"
        directory.mkdir()
        rows = [row for row in catalog if row["concrete_class"] == suite
                and (selected_ids is None or row["execution_id"] in selected_ids)]
        port = prepare_port(upstream, rows, lock, directory)
        if port["source_path"] in source_paths:
            raise ValueError("multiple selected classes share a source file; use a verified multi-class driver")
        source_paths.add(port["source_path"])
        ports.append(port)
    prepared_ids = [identifier for port in ports for identifier in port["execution_ids"]]
    if execution_ids is not None and (len(prepared_ids) != len(set(prepared_ids))
                                      or set(prepared_ids) != set(execution_ids)):
        raise ValueError("prepared suites omit an expected concrete execution")
    driver = ["fun main() {"]
    for port in ports:
        lines = Path(port["driver_path"]).read_text().splitlines()
        if lines[0] != "fun main() {" or lines[-1] != "}":
            raise ValueError("unexpected generated direct driver")
        driver.extend(lines[1:-1])
    driver += ["}", ""]
    (output / "CombinedDriver.kt").write_text("\n".join(driver))
    return ports


def parse_suite_results(text: str, ports: list[dict]) -> list[dict]:
    results = []
    for port in ports:
        results.extend(parse_events(text, port["execution_ids"], port["event_token"]))
    ids = [row["execution_id"] for row in results]
    if len(set(ids)) != len(ids):
        raise ValueError("duplicate execution ID across suites")
    return results


def compiler_resource_bundle(compiler: Path, explicit: Path | None) -> Path | None:
    if explicit:
        candidates = [explicit.resolve()]
    else:
        directory = compiler.resolve().parent
        candidates = [directory / "KSwiftK_CompilerCore.resources",
                      directory / "KSwiftK_CompilerCore.bundle"]
    for candidate in candidates:
        if (candidate / "Stdlib").is_dir():
            return candidate
        resource_path = candidate / "Contents" / "Resources"
        if (resource_path / "Stdlib").is_dir():
            return resource_path
    if explicit:
        raise ValueError("compiler resource bundle must contain Stdlib")
    return None


def add_execution_provenance(results: list[dict], selected_rows: list[dict],
                             ports: list[dict], lock: dict, executable_sha256: str | None,
                             compiled_driver_sha256: str) -> list[dict]:
    source_outputs = {}
    for port in ports:
        if "original_sources" in port:
            for source in port["original_sources"]:
                source_outputs[source["source_path"]] = {
                    "port_sha256": source["port_sha256"], "driver_sha256": port.get("driver_sha256")}
        else:
            source_outputs[port["source_path"]] = {
                "port_sha256": port["port_sha256"], "driver_sha256": port.get("driver_sha256")}
    lock_records = {row["path"]: row for row in lock["upstream_files"]}
    selected_by_id = {row["execution_id"]: row for row in selected_rows}
    if len(selected_by_id) != len(selected_rows):
        raise ValueError("selected catalog contains duplicate execution IDs")
    results_by_id = {}
    for result in results:
        row = selected_by_id.get(result["execution_id"])
        if row is None:
            raise ValueError("result contains an execution ID outside the selected catalog")
        record = lock_records.get(row["upstream_path"])
        output = source_outputs.get(row["upstream_path"])
        if record is None or output is None:
            raise ValueError("selected execution source provenance is incomplete")
        result.update({
            "source_function_id": row.get("upstream_id"),
            "concrete_class": row["concrete_class"],
            "declaring_class": row["declaring_class"],
            "source_path": row["upstream_path"],
            "source_sha256": record["sha256"],
            "source_git_blob_sha": record["git_blob_sha"],
            "candidate_port_sha256": output["port_sha256"],
            "driver_sha256": compiled_driver_sha256,
            "suite_driver_sha256": output["driver_sha256"],
            "candidate_executable_sha256": executable_sha256,
            "catalog_row_sha256": canonical_sha256(row),
        })
        results_by_id[result["execution_id"]] = result
    if len(results_by_id) != len(results) or set(results_by_id) != set(selected_by_id):
        raise ValueError("result execution IDs do not match the selected catalog IDs")
    return [results_by_id[identifier] for identifier in selected_by_id]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--compiler-resource-bundle", type=Path,
                        help="actual Bundle.module directory; defaults to the compiler's sibling resources/bundle")
    parser.add_argument("--suite", action="append", help="select a concrete suite; may be repeated")
    parser.add_argument("--source-function-id", action="append", default=[],
                        help="select all concrete catalog executions for an upstream source ID (path#function)")
    parser.add_argument("--execution-id", action="append", default=[],
                        help="select one concrete catalog execution ID; may be repeated")
    parser.add_argument("--native-catalog", choices=["linux", "macos"],
                        help="use the audited factory/lifecycle driver; without suite or ID selectors runs the full target catalog")
    parser.add_argument("--source-closure-index", type=Path,
                        help="explicit audited source closure for selected Native suites; never full catalog coverage")
    parser.add_argument("--isolated-filesystem", action="store_true",
                        help="run in an owned empty working directory with owned TMPDIR (file suites)")
    parser.add_argument("--support-source", type=Path, action="append", default=[],
                        help="explicit additional test support; hashes are pinned and originals remain unchanged")
    parser.add_argument("--output", type=Path, required=True)
    stdlib = parser.add_mutually_exclusive_group(required=True)
    stdlib.add_argument("--stdlib-library", type=Path)
    stdlib.add_argument("--stdlib-from-source", action="store_true")
    parser.add_argument("--test-library", action="store_true",
                        help="compile original bodies to .kklib, then compile a separate consumer driver")
    parser.add_argument("--optimization", choices=["O0", "O2"], default="O0")
    parser.add_argument("--compile-timeout", type=float, default=240)
    parser.add_argument("--run-timeout", type=float, default=30)
    args = parser.parse_args(argv)
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    root = args.package_root.resolve()
    lock_path = HERE / "reference-lock.json"
    catalog_path = HERE / "native-executions.expected.json"
    declaration_path = HERE / "candidate-declarations.json"
    summary = {"kind": "candidate-assertion-direct-suites", "paired_pass_count": 0,
               "paired_disposition": "UNMAPPED", "seven_observations_exported": False,
               "host": platform.platform(), "python_version": sys.version,
               "optimization": args.optimization, "package_root": str(root),
               "stdlib_mode": "source" if args.stdlib_from_source else "library",
               "test_body_mode": "library-consumer" if args.test_library else "source",
               "runtime_cache_provenance": "Runtime source hashes only; cached object bytes are outside this proof",
               "native_catalog_target": args.native_catalog}
    try:
        if not args.native_catalog and not args.suite and not (args.source_function_id or args.execution_id):
            raise ValueError("direct mode requires --suite or an explicit ID selection")
        if args.native_catalog and platform.system() != {"linux": "Linux", "macos": "Darwin"}[args.native_catalog]:
            raise ValueError("Native catalog must execute on its target host")
        if any(not math.isfinite(value) or value <= 0 for value in [args.compile_timeout, args.run_timeout]):
            raise ValueError("timeouts must be finite and positive")
        if args.stdlib_library and (not args.stdlib_library.is_dir() or
                                   not (args.stdlib_library / "manifest.json").is_file()):
            raise ValueError("stdlib must be a library directory containing manifest.json")
        resources = compiler_resource_bundle(args.compiler, args.compiler_resource_bundle)
        if args.stdlib_from_source and resources is None:
            raise ValueError("source mode requires the actual compiler resource bundle")
        summary["compiler_resource_bundle"] = str(resources) if resources else None
        summary["compiler_resource_bundle_provenance"] = (
            "explicit caller-selected Bundle.module directory" if args.compiler_resource_bundle
            else "compiler sibling Bundle.module directory" if resources
            else "not found; library lane only")
        lock = json.loads(lock_path.read_text())
        for record in lock["upstream_files"]:
            verify_file(args.upstream / record["path"], record)
        verify_file(catalog_path, {"sha256": lock["native_execution_catalog_sha256"]})
        catalog = json.loads(catalog_path.read_text())
        if args.source_closure_index and not args.native_catalog:
            raise ValueError("scoped source closure requires the Native catalog lifecycle driver")
        closure = json.loads(args.source_closure_index.read_text()) if args.source_closure_index else None
        selected_rows = select_catalog_rows(
            catalog, args.suite, args.native_catalog,
            source_function_ids=args.source_function_id,
            execution_ids=args.execution_id)
        selected_ids = [row["execution_id"] for row in selected_rows]
        selected_suites = sorted({row["concrete_class"] for row in selected_rows})
        if args.source_function_id or args.execution_id:
            selection_mode = "explicit-ids"
        elif args.suite:
            selection_mode = "suite"
        else:
            selection_mode = "full-target-catalog"
        selection = make_selection_manifest(
            catalog, selected_rows, args.native_catalog, selection_mode,
            args.source_function_id, args.execution_id, sha256(catalog_path),
            source_file_sha256={row["path"]: row["sha256"] for row in lock["upstream_files"]},
            upstream_commit=lock["commit"], reference_lock_sha256=sha256(lock_path))
        if args.native_catalog:
            suites_for_catalog = args.suite
            if suites_for_catalog is None and selection_mode == "explicit-ids":
                suites_for_catalog = selected_suites
            ports = prepare_catalog(args.upstream, catalog, lock, suites_for_catalog, args.output,
                                    args.native_catalog, json.loads(declaration_path.read_text()),
                                    source_closure=closure, execution_ids=selected_ids)
            summary["kind"] = ("candidate-assertion-native-scoped-catalog"
                                if closure or not selection["covers_full_catalog"]
                                else "candidate-assertion-native-catalog")
        else:
            suites_for_direct = args.suite if args.suite is not None else selected_suites
            ports = prepare_suites(args.upstream, catalog, lock, suites_for_direct, args.output,
                                   execution_ids=selected_ids)
        prepared_ids = [identifier for port in ports for identifier in port["execution_ids"]]
        if len(prepared_ids) != len(set(prepared_ids)) or set(prepared_ids) != set(selected_ids):
            raise ValueError("prepared candidate IDs do not match the selected catalog IDs")
        selection_path = args.output / "selection.json"
        driver = args.output / "CombinedDriver.kt"
        source_paths = [path for port in ports for path in port.get("source_ports", [port.get("port_path")])]
        if len(set(source_paths)) != len(source_paths):
            raise ValueError("each original source must compile only once")

        support_sources = [path.resolve() for path in args.support_source]
        if len(set(support_sources)) != len(support_sources):
            raise ValueError("test support sources must be unique")
        if any(not path.is_file() or path.suffix != ".kt" for path in support_sources):
            raise ValueError("each test support source must be an existing Kotlin file")
        if set(support_sources) & {Path(path).resolve() for path in source_paths}:
            raise ValueError("test support must not replace an original source")

        def inputs(include_selection_manifest: bool = True) -> dict:
            revision = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                                      capture_output=True, text=True, check=False)
            values = {
                "workspace_git_sha": revision.stdout.strip() if revision.returncode == 0 else None,
                "compiler_sha256": sha256(args.compiler),
                "compiler_resource_bundle_sha256": tree_hash(resources) if resources else None,
                "stdlib_content_sha256": tree_hash(args.stdlib_library) if args.stdlib_library else None,
                "stdlib_sources_sha256": tree_hash(root / "Sources" / "CompilerCore" / "Stdlib"),
                "runtime_sources_sha256": tree_hash(root / "Sources" / "Runtime"),
                "runtime_abi_sources_sha256": tree_hash(root / "Sources" / "RuntimeABI"),
                "package_manifest_sha256": sha256(root / "Package.swift"),
                "lock_sha256": sha256(lock_path), "catalog_sha256": sha256(catalog_path),
                "runner_sha256": sha256(Path(__file__)),
                "direct_runner_sha256": sha256(HERE / "run_candidate_subset.py"),
                "helper_sha256": sha256(HERE / "run_jvm_reference.py"),
                "driver_sha256": sha256(driver),
                "support_source_sha256": {str(path): sha256(path) for path in support_sources},
                "source_closure_index_sha256": sha256(args.source_closure_index) if args.source_closure_index else None,
                "port_sha256": {path: sha256(Path(path)) for path in source_paths},
                "catalog_preparer_sha256": sha256(HERE / "prepare_candidate_catalog.py") if args.native_catalog else None,
                "declaration_index_sha256": sha256(declaration_path) if args.native_catalog else None,
            }
            if include_selection_manifest:
                values["selection_manifest_sha256"] = sha256(selection_path)
            return values

        selection["input_hashes"] = inputs(include_selection_manifest=False)
        selection_path.write_text(json.dumps(selection, indent=2, ensure_ascii=False) + "\n")
        summary.update({"selection": selection, "selection_manifest": str(selection_path),
                        "selection_manifest_sha256": sha256(selection_path),
                        "catalog_execution_count": selection["catalog_execution_count"],
                        "target_catalog_execution_count": selection["target_catalog_execution_count"],
                        "selected_execution_count": selection["selected_execution_count"],
                        "selected_source_function_count": len(selection["selected_source_function_ids"]),
                        "covers_full_catalog": selection["covers_full_catalog"],
                        "selection_mode": selection_mode})
        before = inputs()
        count = len(selected_ids)
        summary.update({"workspace_git_sha": before["workspace_git_sha"],
                        "ports": ports, "inputs": before, "expected_count": count})
        base = [str(args.compiler.resolve()), "-" + args.optimization]
        base += ["--stdlib-from-source"] if args.stdlib_from_source else ["--stdlib-library", str(args.stdlib_library.resolve())]
        environment = {"KSWIFTK_PACKAGE_ROOT": str(root)}
        binary = args.output / "candidate"
        sources = source_paths + [str(path) for path in support_sources]
        results = [{"execution_id": identifier, "status": "NOT_RUN"}
                   for port in ports for identifier in port["execution_ids"]]
        library = None
        library_ready = False
        executable_sha256 = None
        if args.test_library:
            library = args.output / "OriginalTests.kklib"
            code = execute(base + ["--emit", "library", "-m", "KioOriginalTests"] + sources + ["-o", str(library)],
                           args.output, "library-compile", args.compile_timeout, environment)
            summary["library_compile_exitcode"] = code
            library_ready = code == 0
            if library_ready:
                summary["test_library_sha256"] = tree_hash(library)
            command = base + ["-I", str(library), str(driver), "-o", str(binary)]
        else:
            command = base + sources + [str(driver), "-o", str(binary)]
        if not args.test_library or library_ready:
            code = execute(command, args.output, "compile", args.compile_timeout, environment)
            summary["compile_exitcode"] = code
        if code == 0:
            executable_sha256 = sha256(binary)
            summary["executable_sha256"] = executable_sha256
            if args.isolated_filesystem:
                work = args.output / "execution"
                work.mkdir()
                temporary = work / "tmp"
                temporary.mkdir()
                code = execute([str(binary)], args.output, "run", args.run_timeout,
                               {"TMPDIR": str(temporary.resolve())}, working_directory=work)
                summary["filesystem_isolation"] = {"cwd": str(work), "TMPDIR": str(temporary)}
            else:
                code = execute([str(binary)], args.output, "run", args.run_timeout)
            summary["run_exitcode"] = code
            results = parse_suite_results((args.output / "run.stdout").read_text(), ports)
            if sha256(binary) != summary["executable_sha256"]:
                raise ValueError("candidate executable changed during execution")
        for record in lock["upstream_files"]:
            verify_file(args.upstream / record["path"], record)
        if inputs() != before or (library_ready and tree_hash(library) != summary["test_library_sha256"]):
            raise ValueError("candidate inputs changed during execution")
        results = add_execution_provenance(results, selected_rows, ports, lock, executable_sha256,
                                           before["driver_sha256"])
        full_catalog_validation = {"status": "NOT_REQUIRED"}
        if selection["covers_full_catalog"]:
            try:
                validate_full_catalog_artifact(
                    selection, results,
                    [row["execution_id"] for row in target_catalog_rows(catalog, args.native_catalog)])
                full_catalog_validation = {"status": "PASS"}
            except ValueError as error:
                full_catalog_validation = {"status": "FAIL", "error": str(error)}
        (args.output / "results.json").write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
        summary.update({"counts": dict(collections.Counter(row["status"] for row in results)),
                        "inputs_unchanged": True,
                        "candidate_executions": sum(row["status"] in {"PASS", "FAIL"} for row in results),
                        "result_execution_ids": [row["execution_id"] for row in results],
                        "full_catalog_validation": full_catalog_validation})
        summary["status"] = "PASS" if (code == 0 and len(results) == count
                                         and all(row["status"] == "PASS" for row in results)
                                         and full_catalog_validation["status"] in {"PASS", "NOT_REQUIRED"}) else "FAIL"
        return 0 if summary["status"] == "PASS" else 1
    except (OSError, ValueError, KeyError) as error:
        summary.update({"status": "ERROR", "error": str(error)})
        return 1
    finally:
        (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    sys.exit(main())
