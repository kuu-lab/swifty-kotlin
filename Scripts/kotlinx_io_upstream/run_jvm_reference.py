#!/usr/bin/env python3
"""Compile and execute the unchanged, hash-locked upstream JVM/common tests.

This is reference validation, not a paired KSwiftK PASS. The exported concrete
execution IDs retain inherited factory suites and all original test bodies.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import signal
import subprocess
import sys
import time
import urllib.request


HERE = Path(__file__).resolve().parent


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_file(path: Path, record: dict) -> None:
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != record["sha256"]:
        raise ValueError(f"SHA-256 mismatch: {path}")
    if "git_blob_sha" in record:
        actual = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        if actual != record["git_blob_sha"]:
            raise ValueError(f"Git blob mismatch: {path}")


def execute(command: list[str], output: Path, stage: str, timeout: float, environment: dict | None = None) -> int:
    (output / f"{stage}.command.json").write_text(json.dumps(command, indent=2) + "\n")
    started = time.monotonic()
    timed_out = False
    overrides = environment or {}
    (output / f"{stage}.env.json").write_text(json.dumps(overrides, indent=2) + "\n")
    with (output / f"{stage}.stdout").open("wb") as stdout, (output / f"{stage}.stderr").open("wb") as stderr:
        child = subprocess.Popen(command, stdout=stdout, stderr=stderr, start_new_session=True,
            env={**os.environ, **overrides})
        try:
            code = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
            # A descendant can remain even if the direct child has exited.
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()
            code = 124
    (output / f"{stage}.result.json").write_text(json.dumps({
        "exitcode": code, "timeout": timed_out, "seconds": round(time.monotonic() - started, 3),
    }, indent=2) + "\n")
    return code


def source_lookup(upstream: Path, seed: dict) -> dict[tuple[str, str], dict]:
    lookup = {}
    for row in seed["cases"]:
        source = upstream / row["upstream_path"]
        package = re.search(r"^package\s+([\w.]+)", source.read_text(), re.MULTILINE)
        if not package:
            raise ValueError(f"no package declaration: {source}")
        for owner in row["upstream_metadata"]["suite_class_names"]:
            key = (package[1] + "." + owner, row["upstream_id"].split("#", 1)[1])
            candidates = lookup.setdefault(key, [])
            if not any(candidate["upstream_id"] == row["upstream_id"] for candidate in candidates):
                candidates.append(row)
    return lookup


def map_executions(discovered: list[dict], results: list[dict], lookup: dict, expected: list[dict]) -> list[dict]:
    expected_ids = {row["execution_id"] for row in expected}
    actual_ids = {row["execution_id"] for row in discovered}
    if expected_ids != actual_ids:
        missing = sorted(expected_ids - actual_ids)
        unexpected = sorted(actual_ids - expected_ids)
        raise ValueError(f"NOT_DISCOVERED={len(missing)} {missing[:10]}; UNEXPECTED={len(unexpected)} {unexpected[:10]}")
    outcomes = {row["execution_id"]: row for row in results}
    if len(outcomes) != len(results):
        raise ValueError("duplicate reference result ID")
    seen = set()
    mapped = []
    for execution in discovered:
        identifier = execution["execution_id"]
        if identifier in seen:
            raise ValueError(f"duplicate discovered execution: {identifier}")
        seen.add(identifier)
        key = (execution.get("declaring_class"), execution.get("method_name"))
        if key not in lookup:
            raise ValueError(f"unmapped concrete upstream method: {key}")
        candidates = lookup[key]
        if len(candidates) != 1:
            raise ValueError(f"ambiguous executed upstream method: {key}")
        source = candidates[0]
        outcome = outcomes.pop(identifier, None)
        mapped.append({
            **execution,
            "upstream_id": source["upstream_id"],
            "upstream_path": source["upstream_path"],
            "git_blob_sha": source["upstream_metadata"]["git_blob_sha"],
            "source_set": source["platform"],
            "original_assertions": "unchanged upstream test body and helpers",
            "factory_expansion": "concrete JUnit class; constructor and inherited methods unchanged",
            "reference_result": outcome or {"status": "NOT_RUN"},
            "candidate_disposition": "unmapped",
            "candidate_reason": "No verified KSwiftK port preserving this upstream assertion body yet.",
        })
    if outcomes:
        raise ValueError(f"unexpected reference results, including failed containers: {list(outcomes)}")
    return mapped


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--kotlin-home", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--download", action="store_true", help="download missing locked Maven jars")
    parser.add_argument("--compile-timeout", type=float, default=180)
    parser.add_argument("--run-timeout", type=float, default=180)
    args = parser.parse_args(argv)
    args.output.mkdir(parents=True, exist_ok=False)
    lock_path = HERE / "reference-lock.json"
    lock = json.loads(lock_path.read_text())
    seed = json.loads((HERE / "coverage-map.seed.json").read_text())
    try:
        for row in lock["upstream_files"]:
            verify_file(args.upstream / row["path"], row)
        for row in lock["sdk_files"]:
            verify_file(args.kotlin_home / row["path"], row)
        args.dependencies.mkdir(parents=True, exist_ok=True)
        jars = []
        for artifact in lock["jvm_artifacts"]:
            target = args.dependencies / artifact["url"].rsplit("/", 1)[1]
            if not target.exists() and args.download:
                with urllib.request.urlopen(artifact["url"], timeout=60) as response:
                    target.write_bytes(response.read())
            verify_file(target, artifact)
            jars.append(target.resolve())
        lookup = source_lookup(args.upstream, seed)
        catalog_path = HERE / "jvm-executions.expected.json"
        verify_file(catalog_path, {"sha256": lock["jvm_execution_catalog_sha256"]})
        expected = json.loads(catalog_path.read_text())
        eligible = {row["upstream_id"] for row in seed["cases"]
            if row["platform"] in {"common", "jvm"} and "Windows" not in row["upstream_path"]}
        if {row["upstream_id"] for row in expected} != eligible:
            raise ValueError("expected execution catalog does not cover every eligible upstream function ID")
        sources = sorted({row["upstream_path"] for row in seed["cases"]
            if row["platform"] in {"common", "jvm"} and "Windows" not in row["upstream_path"]}
            | {row["path"] for row in seed["inventory_only_sources"]
                if any(part in row["path"] for part in ("/common/test/", "/jvm/test/"))
                and "Windows" not in row["path"]})
        common = [str((args.upstream / source).resolve()) for source in sources if "/common/" in source]
        tests_jar = (args.output / "upstream-jvm-tests.jar").resolve()
        sdk = args.kotlin_home.resolve() / "lib"
        io_jars = [jar for jar in jars if jar.name.startswith("kotlinx-io-")]
        compile_cp = jars + [sdk / "kotlin-test.jar", sdk / "kotlin-test-junit5.jar"]
        command = [str(args.kotlin_home.resolve() / "bin/kotlinc")]
        command += [str((args.upstream / source).resolve()) for source in sources]
        command += ["-classpath", os.pathsep.join(map(str, compile_cp)), "-Xmulti-platform",
            "-Xexpect-actual-classes", "-Xcommon-sources=" + ",".join(common),
            "-Xfriend-paths=" + ",".join(map(str, io_jars)), "-opt-in=kotlinx.io.InternalIoApi",
            "-opt-in=kotlin.ExperimentalStdlibApi", "-XXLanguage:+UnnamedLocalVariables", "-d", str(tests_jar)]
        environment = {"schema_version": 1, "kind": "reference-only", "kotlin": lock["kotlin"],
            "kotlinx_io": lock["kotlinx_io"], "upstream_commit": lock["commit"],
            "reference_lock_sha256": sha256(lock_path), "coverage_map_sha256": sha256(HERE / "coverage-map.seed.json"),
            "runner_sha256": sha256(HERE / "JvmReferenceRunner.java"), "host": platform.platform(),
            "java": str(args.java.resolve()), "source_files": sources,
            "unsupported_source_files": [row["path"] for row in lock["upstream_files"] if row["path"] not in sources],
            "sdk_files": lock["sdk_files"], "reference_artifacts": lock["jvm_artifacts"]}
        compiler_environment = {"JAVACMD": str(args.java.resolve())}
        environment["compiler_environment"] = compiler_environment
        (args.output / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
        if execute([str(args.java.resolve()), "-version"], args.output, "java-version", 10):
            return 1
        java_version = (args.output / "java-version.stderr").read_text()
        if not re.search(r'version "21[.\"]', java_version):
            raise ValueError("JVM reference requires Java 21")
        if execute([str(args.kotlin_home.resolve() / "bin/kotlinc"), "-version"],
            args.output, "kotlin-version", 30, compiler_environment):
            return 1
        compiler_version = (args.output / "kotlin-version.stderr").read_text() + (args.output / "kotlin-version.stdout").read_text()
        if not re.search(r"kotlinc-jvm 2\.3\.10(?:\s|$)", compiler_version):
            raise ValueError("JVM reference requires Kotlin 2.3.10")
        if execute(command, args.output, "compile", args.compile_timeout, compiler_environment):
            return 1
        runtime_cp = jars + [tests_jar] + [sdk / name for name in
            ("kotlin-stdlib.jar", "kotlin-reflect.jar", "kotlin-test.jar", "kotlin-test-junit5.jar")]
        command = [str(args.java.resolve()), "-Xmx1024m", "-cp", os.pathsep.join(map(str, runtime_cp)),
            str(HERE / "JvmReferenceRunner.java"), str(tests_jar), str(args.output.resolve() / "junit")]
        code = execute(command, args.output, "run", args.run_timeout)
        output = args.output / "junit"
        if not (output / "results.json").exists():
            return 1
        mapped = map_executions(json.loads((output / "discovered.json").read_text()),
            json.loads((output / "results.json").read_text()), lookup, expected)
        (args.output / "execution-map.json").write_text(json.dumps(mapped, indent=2) + "\n")
        reference_counts = dict(collections.Counter(row["reference_result"]["status"] for row in mapped))
        summary = {"kind": "reference-only", "concrete_execution_count": len(mapped),
            "unique_upstream_function_ids": len({row["upstream_id"] for row in mapped}),
            "reference_counts": reference_counts, "candidate_counts": {"UNMAPPED": len(mapped)},
            "paired_pass_count": 0, "source_files_compiled": len(sources)}
        (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(json.dumps(summary))
        return 0 if code == 0 and reference_counts == {"PASS": len(mapped)} else 1
    except (OSError, ValueError, KeyError) as error:
        print(f"JVM reference: {error}", file=sys.stderr)
        (args.output / "error.txt").write_text(str(error) + "\n")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
