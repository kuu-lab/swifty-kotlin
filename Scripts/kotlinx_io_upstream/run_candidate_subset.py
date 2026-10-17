#!/usr/bin/env python3
"""Execute a locked direct upstream suite without replacing its assertions.

This reports candidate assertion execution only. It does not export the seven
paired observations, so paired PASS remains zero. Inherited factories, test
hooks and parameterized methods require a different verified driver.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import platform
import re
import subprocess
import sys

from run_jvm_reference import HERE, execute, sha256, verify_file


PREFIX = b'@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")\n\n'
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z_0-9]*\Z")
KUU_2566_METHODS = frozenset({
    "readFromDoesNotLeaveEmptyTailSegment",
    "bufferInputStreamByteByByte",
    "bufferInputStreamBulkReads",
    "copyToOutputStream",
    "copyToOutputStreamWithStartIndex",
    "copyToOutputStreamWithEndIndex",
    "copyToOutputStreamWithIndices",
    "copyToOutputStreamWithEmptyRange",
    "readToOutputStream",
    "readToOutputStreamWithByteCount",
})


def matching_kotlin_brace(text: str, opening: int) -> int:
    depth = 0
    state = "code"
    block_comment_depth = 0
    index = opening
    while index < len(text):
        if state == "code":
            if text.startswith("//", index):
                state = "line-comment"
                index += 2
                continue
            if text.startswith("/*", index):
                state = "block-comment"
                block_comment_depth = 1
                index += 2
                continue
            if text.startswith('"""', index):
                state = "raw-string"
                index += 3
                continue
            if text[index] == '"':
                state = "string"
                index += 1
                continue
            if text[index] == "'":
                state = "character"
                index += 1
                continue
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    return index
        elif state == "line-comment":
            if text[index] == "\n":
                state = "code"
        elif state == "block-comment":
            if text.startswith("/*", index):
                block_comment_depth += 1
                index += 2
                continue
            if text.startswith("*/", index):
                block_comment_depth -= 1
                index += 2
                if block_comment_depth == 0:
                    state = "code"
                continue
        elif state == "raw-string":
            if text.startswith('"""', index):
                state = "code"
                index += 3
                continue
        elif state in {"string", "character"}:
            if text[index] == "\\":
                index += 2
                continue
            if (state == "string" and text[index] == '"') or (state == "character" and text[index] == "'"):
                state = "code"
        index += 1
    raise ValueError("selected test method has an unclosed body")


def extract_selected_test_methods(text: str, method_names: list[str]) -> tuple[str, list[dict]]:
    if not method_names or len(method_names) != len(set(method_names)):
        raise ValueError("method source closure requires unique selected methods")
    if not set(method_names) <= KUU_2566_METHODS:
        raise ValueError("method source closure only supports the locked KUU-2566 BufferTest methods")
    package = re.search(r"(?m)^package\s+kotlinx\.io\s*$", text)
    segment_size = re.search(r"(?m)^private const val SEGMENT_SIZE = Segment\.SIZE\s*$", text)
    if package is None or segment_size is None:
        raise ValueError("BufferTest method source closure is missing its locked package or SEGMENT_SIZE declaration")
    imports = re.findall(r"(?m)^import\s+[^\r\n]+$", text)
    prelude = package.group(0) + "\n\n" + "\n".join(imports) + "\n\n" + segment_size.group(0)
    method_records = []
    method_blocks = []
    for method_name in method_names:
        declaration = re.compile(
            r"(?m)^[ \t]*@Test[ \t]*\r?\n[ \t]*fun[ \t]+" + re.escape(method_name)
            + r"[ \t]*\([ \t]*\)[ \t]*\{"
        )
        matches = list(declaration.finditer(text))
        if len(matches) != 1:
            raise ValueError(f"selected original test declaration must occur exactly once: {method_name}")
        match = matches[0]
        opening = match.end() - 1
        closing = matching_kotlin_brace(text, opening)
        source_region = text[match.start():closing + 1]
        method_blocks.append(source_region)
        method_records.append({
            "method_name": method_name,
            "source_line_start": text.count("\n", 0, match.start()) + 1,
            "source_line_end": text.count("\n", 0, closing) + 1,
            "source_region_sha256": hashlib.sha256(source_region.encode("utf-8")).hexdigest(),
            "source_region_preserved_exactly": True,
        })
    ordered = sorted(zip(method_records, method_blocks), key=lambda item: item[0]["source_line_start"])
    method_records = [record for record, _ in ordered]
    ordered_blocks = [block for _, block in ordered]
    source = prelude + "\n\nclass BufferTest {\n" + "\n".join(
        block for block in ordered_blocks
    ) + "\n}\n"
    return source, method_records


def prepare_port(upstream: Path, rows: list[dict], lock: dict, output: Path,
                 method_source_closure: bool = False) -> dict:
    if not rows:
        raise ValueError("suite has no locked execution IDs")
    suite = rows[0]["concrete_class"]
    if not all(IDENTIFIER.fullmatch(part) for part in suite.split(".")):
        raise ValueError("unsupported Kotlin class identifier")
    if any(row["concrete_class"] != suite or row["declaring_class"] != suite
           or row["parameter_types"] for row in rows):
        raise ValueError("inherited factories and parameterized methods need a verified driver")
    paths = {row["upstream_path"] for row in rows}
    if len(paths) != 1:
        raise ValueError("direct suite must have one original source file")
    path = paths.pop()
    record = next((row for row in lock["upstream_files"] if row["path"] == path), None)
    if record is None:
        raise ValueError("source is absent from reference lock")
    source = upstream / path
    verify_file(source, record)
    raw = source.read_bytes()
    text = raw.decode("utf-8")
    if re.search(r"^\s*@(?:[\w.]*\.)?(?:BeforeTest|AfterTest|BeforeEach|AfterEach|TempDir)\b", text, re.MULTILINE):
        raise ValueError("test hooks require a verified lifecycle driver")
    methods = [row["method_name"] for row in rows]
    identifiers = [row["execution_id"] for row in rows]
    if len(set(methods)) != len(rows) or len(set(identifiers)) != len(rows):
        raise ValueError("duplicate locked execution ID or method")
    for row in rows:
        method = row["method_name"]
        native_execution_id = suite + "." + method
        jvm_execution_id = f"[engine:junit-jupiter]/[class:{suite}]/[method:{method}()]"
        if not IDENTIFIER.fullmatch(method) or row["execution_id"] not in {native_execution_id, jvm_execution_id}:
            raise ValueError("unsupported execution/method identifier")
        if row["git_blob_sha"] != record["git_blob_sha"]:
            raise ValueError("catalog/source blob mismatch")
        if not re.search(r"\bfun\s+" + re.escape(method) + r"\s*\(\s*\)", text):
            raise ValueError("locked method is not a parameterless source declaration")
    method_records = []
    if method_source_closure:
        if suite != "kotlinx.io.BufferTest":
            raise ValueError("method source closure is only supported for kotlinx.io.BufferTest")
        source_body, method_records = extract_selected_test_methods(text, methods)
        port_bytes = PREFIX + source_body.encode("utf-8")
    else:
        port_bytes = PREFIX + raw
    port = output / source.name
    port.write_bytes(port_bytes)
    token = "KIO_" + hashlib.sha256(raw + suite.encode()).hexdigest()[:24]
    driver = ["fun main() {"]
    for row in rows:
        identifier = row["execution_id"]
        driver += [
            f'    println("{token} BEGIN {identifier}")',
            "    try {",
            f'        {suite}().{row["method_name"]}()',
            f'        println("{token} PASS {identifier}")',
            "    } catch (failure: Throwable) {",
            f'        println("{token} FAIL {identifier}")',
            f'        println("{token} EXCEPTION " + failure::class.qualifiedName)',
            "    }",
        ]
    driver += ["}", ""]
    driver_path = output / "CandidateDriver.kt"
    driver_path.write_text("\n".join(driver), encoding="utf-8")
    result = {
        "suite": suite, "source_path": path, "source_sha256": record["sha256"],
        "source_git_blob_sha": record["git_blob_sha"], "prefix_bytes": len(PREFIX),
        "assertions_parameters_constructors_changed": False,
        "constructor_policy": "fresh original class instance per test",
        "port_path": str(port), "port_sha256": sha256(port),
        "driver_path": str(driver_path), "driver_sha256": sha256(driver_path),
        "execution_ids": identifiers, "event_token": token,
    }
    if method_source_closure:
        result["source_port_mode"] = "selected-original-test-method-closure"
        result["selected_method_source_records"] = method_records
        result["complete_original_file_compiled"] = False
    else:
        result["source_port_mode"] = "complete-original-source-file"
        result["complete_original_file_compiled"] = True
        result["original_bytes_preserved_as_suffix"] = port_bytes[len(PREFIX):] == raw
    return result


def parse_events(text: str, identifiers: list[str], token: str) -> list[dict]:
    results = []
    current = None
    for line in text.splitlines(keepends=True):
        if not line.startswith(token + " "):
            if current is not None:
                current["stdout"] += line
            continue
        event = line.rstrip("\r\n")[len(token) + 1:]
        kind, _, value = event.partition(" ")
        if kind == "BEGIN":
            if current is not None or len(results) >= len(identifiers) or value != identifiers[len(results)]:
                raise ValueError("missing, duplicate or unexpected execution event")
            current = {"execution_id": value, "status": "NOT_FINISHED", "stdout": "", "exception_type": None}
        elif kind in {"PASS", "FAIL"}:
            if current is None or value != current["execution_id"]:
                raise ValueError("result event without the expected active test")
            current["status"] = kind
            results.append(current)
            current = None
        elif kind == "EXCEPTION":
            if not results or results[-1]["status"] != "FAIL" or results[-1]["exception_type"] is not None:
                raise ValueError("unexpected exception event")
            results[-1]["exception_type"] = value
        else:
            raise ValueError("unknown execution event")
    if current is not None:
        results.append(current)
    seen = {row["execution_id"] for row in results}
    results.extend({"execution_id": identifier, "status": "NOT_RUN", "stdout": "", "exception_type": None}
                   for identifier in identifiers if identifier not in seen)
    return results


def tree_hash(path: Path) -> str:
    if not path.exists():
        raise ValueError(f"missing input path: {path}")
    digest = hashlib.sha256()
    paths = sorted(path.rglob("*")) if path.is_dir() else [path]
    if not any(file.is_file() for file in paths):
        raise ValueError(f"input has no regular files: {path}")
    for file in paths:
        if file.is_file():
            digest.update(str(file.relative_to(path) if path.is_dir() else file.name).encode() + b"\0")
            digest.update(bytes.fromhex(sha256(file)))
    return digest.hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--stdlib-library", type=Path, required=True)
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--suite", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--optimization", choices=["O0", "O2"], default="O0")
    parser.add_argument("--compile-timeout", type=float, default=180)
    parser.add_argument("--run-timeout", type=float, default=30)
    args = parser.parse_args(argv)
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    lock_path = HERE / "reference-lock.json"
    catalog_path = HERE / "native-executions.expected.json"
    lock = json.loads(lock_path.read_text())
    summary = {"kind": "candidate-assertion-subset", "paired_pass_count": 0,
               "paired_disposition": "UNMAPPED", "seven_observations_exported": False,
               "host": platform.platform(), "python_version": sys.version,
               "optimization": args.optimization, "package_root": str(args.package_root.resolve())}
    try:
        if any(not math.isfinite(value) or value <= 0 for value in [args.compile_timeout, args.run_timeout]):
            raise ValueError("timeouts must be finite and positive")
        if not args.stdlib_library.is_dir() or not (args.stdlib_library / "manifest.json").is_file():
            raise ValueError("stdlib must be a library directory containing manifest.json")
        for record in lock["upstream_files"]:
            verify_file(args.upstream / record["path"], record)
        verify_file(catalog_path, {"sha256": lock["native_execution_catalog_sha256"]})
        rows = [row for row in json.loads(catalog_path.read_text()) if row["concrete_class"] == args.suite]
        port = prepare_port(args.upstream, rows, lock, args.output)
        inputs = {
            "compiler_sha256": sha256(args.compiler), "stdlib_content_sha256": tree_hash(args.stdlib_library),
            "lock_sha256": sha256(lock_path), "catalog_sha256": sha256(catalog_path),
            "runner_sha256": sha256(Path(__file__)), "helper_sha256": sha256(HERE / "run_jvm_reference.py"),
            "runtime_sources_sha256": tree_hash(args.package_root / "Sources" / "Runtime"),
            "runtime_abi_sources_sha256": tree_hash(args.package_root / "Sources" / "RuntimeABI"),
            "package_manifest_sha256": sha256(args.package_root / "Package.swift"),
        }
        summary.update({"port": port, "inputs": inputs, "expected_count": len(rows)})
        binary = args.output / "candidate"
        command = [str(args.compiler.resolve()), "--stdlib-library", str(args.stdlib_library.resolve()),
                   "-" + args.optimization, port["port_path"], port["driver_path"], "-o", str(binary)]
        code = execute(command, args.output, "compile", args.compile_timeout,
                       {"KSWIFTK_PACKAGE_ROOT": str(args.package_root.resolve())})
        summary["compile_exitcode"] = code
        results = [{"execution_id": row["execution_id"], "status": "NOT_RUN"} for row in rows]
        if code == 0:
            summary["executable_sha256"] = sha256(binary)
            code = execute([str(binary)], args.output, "run", args.run_timeout)
            summary["run_exitcode"] = code
            results = parse_events((args.output / "run.stdout").read_text(), port["execution_ids"], port["event_token"])
            if sha256(binary) != summary["executable_sha256"]:
                raise ValueError("candidate executable changed during execution")
        for record in lock["upstream_files"]:
            verify_file(args.upstream / record["path"], record)
        after = {**inputs, "compiler_sha256": sha256(args.compiler),
                 "stdlib_content_sha256": tree_hash(args.stdlib_library),
                 "lock_sha256": sha256(lock_path), "catalog_sha256": sha256(catalog_path),
                 "runner_sha256": sha256(Path(__file__)), "helper_sha256": sha256(HERE / "run_jvm_reference.py"),
                 "runtime_sources_sha256": tree_hash(args.package_root / "Sources" / "Runtime"),
                 "runtime_abi_sources_sha256": tree_hash(args.package_root / "Sources" / "RuntimeABI"),
                 "package_manifest_sha256": sha256(args.package_root / "Package.swift")}
        if after != inputs or sha256(Path(port["port_path"])) != port["port_sha256"] or sha256(Path(port["driver_path"])) != port["driver_sha256"]:
            raise ValueError("candidate inputs changed during execution")
        (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        summary["counts"] = dict(collections.Counter(row["status"] for row in results))
        summary["inputs_unchanged"] = True
        summary["status"] = "PASS" if code == 0 and len(results) == len(rows) and all(row["status"] == "PASS" for row in results) else "FAIL"
        return 0 if summary["status"] == "PASS" else 1
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        summary.update({"status": "ERROR", "error": str(error)})
        return 1
    finally:
        (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    sys.exit(main())
