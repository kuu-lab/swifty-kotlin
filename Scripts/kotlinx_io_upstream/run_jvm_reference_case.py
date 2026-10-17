#!/usr/bin/env python3
"""Compile and run one locked upstream JVM test without executing its full suite."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from run_jvm_reference import execute, sha256, verify_file


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def extract_method_source(source: bytes, class_name: str, method_name: str) -> tuple[bytes, bytes]:
    class_match = re.search(
        rb"(?m)^class[ \t]+" + class_name.encode() + rb"[ \t]*\{", source
    )
    if class_match is None:
        raise ValueError(f"class declaration not found: {class_name}")
    method_pattern = re.compile(
        rb"(?m)^[ \t]*@Test[ \t]*\r?\n[ \t]*fun[ \t]+"
        + method_name.encode() + rb"[ \t]*\([ \t]*\)[ \t]*\{"
    )
    methods = list(method_pattern.finditer(source, class_match.end()))
    if len(methods) != 1:
        raise ValueError(f"expected one @Test method declaration: {method_name}")
    method = methods[0]
    depth = 0
    in_string = False
    escaped = False
    end = None
    for index in range(source.index(b"{", method.start()), len(source)):
        byte = source[index]
        if in_string:
            if escaped:
                escaped = False
            elif byte == ord("\\"):
                escaped = True
            elif byte == ord('"'):
                in_string = False
            continue
        if byte == ord('"'):
            in_string = True
        elif byte == ord("{"):
            depth += 1
        elif byte == ord("}"):
            depth -= 1
            if depth == 0:
                end = index + 1
                break
    if end is None:
        raise ValueError(f"unterminated method body: {method_name}")
    exact_method = source[method.start():end]
    prepared = source[:class_match.end()] + b"\n" + exact_method + b"\n}\n"
    return prepared, exact_method


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--kotlin-home", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--upstream-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compile-timeout", type=float, default=180)
    parser.add_argument("--run-timeout", type=float, default=60)
    args = parser.parse_args(argv)

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    java_version = subprocess.run([str(args.java.resolve()), "-version"], text=True,
                                  capture_output=True, check=False)
    version_text = java_version.stdout + java_version.stderr
    version_match = re.search(r'version "(\d+)(?:\.[^"]*)?"', version_text)
    if java_version.returncode != 0 or version_match is None or version_match.group(1) != "21":
        raise SystemExit("the locked upstream JVM test requires a Java 21 runtime")
    lock_path = HERE / "reference-lock.json"
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    catalog_path = HERE / "jvm-executions.expected.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    matches = [row for row in catalog if row.get("upstream_id") == args.upstream_id]
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one locked JVM execution for {args.upstream_id!r}")
    execution = matches[0]
    source_path = execution["upstream_path"]
    source = args.upstream / source_path
    upstream_record = next((row for row in lock["upstream_files"] if row["path"] == source_path), None)
    if upstream_record is None:
        raise SystemExit(f"upstream test is absent from reference lock: {source_path}")
    verify_file(source, upstream_record)
    prepared_source, exact_method = extract_method_source(
        source.read_bytes(), execution["concrete_class"].rsplit(".", 1)[-1], execution["method_name"]
    )

    sdk_files = {}
    for record in lock["sdk_files"]:
        path = args.kotlin_home / record["path"]
        verify_file(path, record)
        sdk_files[record["path"]] = path.resolve()
    artifacts = {}
    for record in lock["jvm_artifacts"]:
        path = args.dependencies / record["url"].rsplit("/", 1)[-1]
        verify_file(path, record)
        artifacts[record["coordinate"]] = path.resolve()

    junit = artifacts["org.junit.platform:junit-platform-console-standalone:1.12.2"]
    io_jars = [path for coordinate, path in artifacts.items() if coordinate.startswith("org.jetbrains.kotlinx:kotlinx-io-")]
    test_libraries = [sdk_files["lib/kotlin-test.jar"], sdk_files["lib/kotlin-test-junit5.jar"]]
    compile_classpath = os.pathsep.join(map(str, [*io_jars, *test_libraries, junit]))
    test_classes = output / "test-classes"
    test_classes.mkdir()
    selected_source = output / "selected-test.kt"
    selected_source.write_bytes(prepared_source)
    kotlin_compile = [
        str(sdk_files["bin/kotlinc"]), str(selected_source.resolve()),
        "-classpath", compile_classpath, "-d", str(test_classes),
    ]
    if execute(kotlin_compile, output, "compile-upstream-test", args.compile_timeout,
               {"JAVA_HOME": str(args.java.resolve().parent.parent)}) != 0:
        raise SystemExit("targeted kotlinc compilation failed")

    javac = args.java.resolve().with_name("javac")
    if not javac.is_file():
        raise SystemExit(f"JDK compiler not found beside Java runtime: {javac}")
    java_compile = [
        str(javac), "--release", "21", "-classpath", str(junit), "-d", str(test_classes),
        str(HERE / "JvmReferenceRunner.java"),
    ]
    if execute(java_compile, output, "compile-junit-runner", args.compile_timeout) != 0:
        raise SystemExit("targeted JUnit runner compilation failed")

    runtime_classpath = os.pathsep.join(map(str, [test_classes, *io_jars, *test_libraries,
                                                    sdk_files["lib/kotlin-stdlib.jar"], junit]))
    selector = execution["concrete_class"] + "#" + execution["method_name"]
    runner_output = output / "junit"
    command = [str(args.java.resolve()), "-cp", runtime_classpath, "JvmReferenceRunner",
               str(test_classes), str(runner_output), selector]
    if execute(command, output, "run-upstream-test", args.run_timeout,
               {"JAVA_HOME": str(args.java.resolve().parent.parent)}) != 0:
        raise SystemExit("targeted upstream JVM test failed or was incomplete")

    discovered = json.loads((runner_output / "discovered.json").read_text(encoding="utf-8"))
    results = json.loads((runner_output / "results.json").read_text(encoding="utf-8"))
    if len(discovered) != 1 or discovered[0].get("execution_id") != execution["execution_id"]:
        raise SystemExit("JUnit selection did not resolve to the locked execution ID")
    if (len(results) != 1 or results[0].get("execution_id") != execution["execution_id"]
            or results[0].get("status") != "PASS"):
        raise SystemExit("targeted original assertion did not pass exactly once")
    if results[0].get("stdout") or results[0].get("stderr"):
        raise SystemExit("targeted original assertion unexpectedly wrote output")

    report = {
        "schema_version": 1,
        "kind": "locked-upstream-jvm-test",
        "upstream_id": args.upstream_id,
        "execution_id": execution["execution_id"],
        "reference_version": lock["kotlinx_io"],
        "reference_commit": lock["commit"],
        "test_source_path": source_path,
        "test_source_sha256": sha256(source),
        "test_source_git_blob_sha": upstream_record["git_blob_sha"],
        "selected_method_source_sha256": hashlib.sha256(exact_method).hexdigest(),
        "prepared_source_sha256": sha256(selected_source),
        "support_sources": [],
        "java_runtime_major": 21,
        "java_version_sha256": hashlib.sha256(version_text.encode()).hexdigest(),
        "jvm_artifact_sha256": {str(path): sha256(path) for path in [*io_jars, junit]},
        "kotlin_sdk_sha256": {path: sha256(value) for path, value in sdk_files.items()},
        "runner_source_sha256": sha256(HERE / "JvmReferenceRunner.java"),
        "compile_stdout_sha256": sha256(output / "compile-upstream-test.stdout"),
        "compile_stderr_sha256": sha256(output / "compile-upstream-test.stderr"),
        "runtime_stdout_sha256": sha256(output / "run-upstream-test.stdout"),
        "runtime_stderr_sha256": sha256(output / "run-upstream-test.stderr"),
        "observed_stdout_sha256": hashlib.sha256(results[0]["stdout"].encode()).hexdigest(),
        "observed_stderr_sha256": hashlib.sha256(results[0]["stderr"].encode()).hexdigest(),
        "discovered_count": len(discovered),
        "executed_count": len(results),
        "passed_count": sum(row.get("status") == "PASS" for row in results),
        "result": "PASS",
        "exit_code": 0,
    }
    report_path = output / "report.json"
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
