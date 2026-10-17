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
import shutil
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


def execute(command: list[str], output: Path, stage: str, timeout: float, environment: dict | None = None,
            working_directory: Path | None = None) -> int:
    (output / f"{stage}.command.json").write_text(json.dumps(command, indent=2) + "\n")
    started = time.monotonic()
    timed_out = False
    overrides = environment or {}
    if working_directory is not None:
        (output / f"{stage}.cwd.json").write_text(json.dumps(str(working_directory.resolve())) + "\n")
    (output / f"{stage}.env.json").write_text(json.dumps(overrides, indent=2) + "\n")
    with (output / f"{stage}.stdout").open("wb") as stdout, (output / f"{stage}.stderr").open("wb") as stderr:
        child = subprocess.Popen(command, stdout=stdout, stderr=stderr, start_new_session=True,
            env={**os.environ, **overrides}, cwd=working_directory)
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


def select_source_function_rows(catalog: list[dict], source_function_ids: list[str] | None) -> list[dict]:
    if not source_function_ids:
        return list(catalog)
    if len(source_function_ids) > 10:
        raise ValueError("at most ten upstream source function IDs may be selected")
    if any(not identifier or identifier != identifier.strip() for identifier in source_function_ids):
        raise ValueError("source function IDs must be nonempty and have no surrounding whitespace")
    if len(source_function_ids) != len(set(source_function_ids)):
        raise ValueError("source function IDs must be unique")
    eligible = [row for row in catalog if row["source_set"] in {"common", "jvm"}
                and "Windows" not in row["upstream_path"]]
    known = {row["upstream_id"] for row in eligible}
    all_known = {row["upstream_id"] for row in catalog}
    for identifier in source_function_ids:
        if identifier not in known:
            if identifier in all_known:
                raise ValueError(f"source function has no JVM execution: {identifier}")
            raise ValueError(f"unknown upstream source function ID: {identifier}")
    selected = set(source_function_ids)
    rows = [row for row in eligible if row["upstream_id"] in selected]
    if {row["upstream_id"] for row in rows} != selected:
        raise ValueError("selected source function IDs do not cover the JVM catalog")
    if len({row["execution_id"] for row in rows}) != len(rows):
        raise ValueError("selected JVM catalog contains duplicate concrete execution IDs")
    return rows


def resolve_compile_sources(all_sources: list[str], requested: list[str], required: set[str]) -> list[str]:
    if not requested:
        return list(all_sources)
    if len(requested) != len(set(requested)):
        raise ValueError("compile source paths must be unique")
    unknown = set(requested) - set(all_sources)
    if unknown:
        raise ValueError(f"compile source path is outside the locked JVM/common source pool: {sorted(unknown)}")
    missing = required - set(requested)
    if missing:
        raise ValueError(f"compile source paths omit selected test sources: {sorted(missing)}")
    return sorted(requested)


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
    parser.add_argument("--javac", type=Path,
                        help="Java compiler used to build the small JUnit launcher with --release 21")
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--download", action="store_true", help="download missing locked Maven jars")
    parser.add_argument("--source-function-id", action="append", default=[],
                        help="select every concrete JVM invocation for an upstream function (path#function)")
    parser.add_argument("--compile-source-path", action="append", default=[],
                        help="compile only this locked source path; may be repeated for a targeted reference closure")
    parser.add_argument("--contract-probe", type=Path,
                        help="compile and run an additional Kotlin probe function after the selected original tests")
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
        catalog = json.loads(catalog_path.read_text())
        expected = select_source_function_rows(catalog, args.source_function_id)
        eligible = {row["upstream_id"] for row in seed["cases"]
            if row["platform"] in {"common", "jvm"} and "Windows" not in row["upstream_path"]}
        if {row["upstream_id"] for row in catalog} != eligible:
            raise ValueError("expected execution catalog does not cover every eligible upstream function ID")
        if args.source_function_id and {row["upstream_id"] for row in expected} != set(args.source_function_id):
            raise ValueError("selected JVM catalog does not cover the requested source function IDs")
        sources = sorted({row["upstream_path"] for row in seed["cases"]
            if row["platform"] in {"common", "jvm"} and "Windows" not in row["upstream_path"]}
            | {row["path"] for row in seed["inventory_only_sources"]
                if any(part in row["path"] for part in ("/common/test/", "/jvm/test/"))
                and "Windows" not in row["path"]})
        sources = resolve_compile_sources(sources, args.compile_source_path,
            {row["upstream_path"] for row in expected})
        contract_probe = args.contract_probe.resolve() if args.contract_probe else None
        if contract_probe is not None:
            if not contract_probe.is_file() or contract_probe.suffix != ".kt":
                raise ValueError("contract probe must be an existing Kotlin source file")
            if not args.source_function_id:
                raise ValueError("contract probe requires a selected source-function run")
            if contract_probe in {Path(args.upstream / source).resolve() for source in sources}:
                raise ValueError("contract probe must be separate from the locked upstream source closure")
        common = [str((args.upstream / source).resolve()) for source in sources if "/common/" in source]
        tests_jar = (args.output / "upstream-jvm-tests.jar").resolve()
        sdk = args.kotlin_home.resolve() / "lib"
        io_jars = [jar for jar in jars if jar.name.startswith("kotlinx-io-")]
        compile_cp = jars + [sdk / "kotlin-test.jar", sdk / "kotlin-test-junit5.jar"]
        command = [str(args.kotlin_home.resolve() / "bin/kotlinc")]
        command += [str((args.upstream / source).resolve()) for source in sources]
        if contract_probe is not None:
            command.append(str(contract_probe))
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
            "sdk_files": lock["sdk_files"], "reference_artifacts": lock["jvm_artifacts"],
            "selected_source_function_ids": sorted(set(args.source_function_id)),
            "selected_execution_ids": [row["execution_id"] for row in expected],
            "contract_probe": ({"path": str(contract_probe), "sha256": sha256(contract_probe),
                                "probe_class": "kotlinx.io.ApiContractProbeKt",
                                "probe_method": "runKuu2563ApiContractProbe"} if contract_probe else None)}
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
        sibling_javac = args.java.resolve().with_name("javac")
        javac_path = args.javac.resolve() if args.javac else sibling_javac if sibling_javac.is_file() else shutil.which("javac")
        if javac_path is None:
            raise ValueError("a javac capable of --release 21 is required to compile the reference launcher")
        javac = Path(javac_path)
        if not javac.is_file():
            raise ValueError("javac path does not name a file")
        runner_classes = (args.output / "runner-classes").resolve()
        runner_classes.mkdir()
        launcher = Path(__file__).resolve().with_name("JvmReferenceRunner.java")
        junit_jar = next(jar for jar in jars if jar.name.startswith("junit-platform-console-standalone-"))
        launcher_command = [str(javac), "--release", "21", "-classpath", str(junit_jar),
            "-d", str(runner_classes), str(launcher)]
        if execute([str(javac), "-version"], args.output, "javac-version", 15):
            return 1
        environment["javac"] = str(javac)
        environment["javac_version"] = ((args.output / "javac-version.stderr").read_text()
            + (args.output / "javac-version.stdout").read_text()).strip()
        environment["launcher_compile_command"] = launcher_command
        (args.output / "environment.json").write_text(json.dumps(environment, indent=2) + "\n")
        if execute(launcher_command, args.output, "launcher-compile", args.compile_timeout):
            return 1
        runtime_cp = jars + [tests_jar] + [sdk / name for name in
            ("kotlin-stdlib.jar", "kotlin-reflect.jar", "kotlin-test.jar", "kotlin-test-junit5.jar")]
        selection_path = args.output / "selected-methods.tsv"
        if args.source_function_id:
            selection_path.write_text("".join(
                f"{row['concrete_class']}\t{row['method_name']}\n" for row in expected
            ), encoding="utf-8")
        command = [str(args.java.resolve()), "-Xmx1024m", "-cp",
            os.pathsep.join(map(str, [runner_classes] + runtime_cp)), "JvmReferenceRunner",
            str(tests_jar), str(args.output.resolve() / "junit")]
        if args.source_function_id:
            command.append(str(selection_path.resolve()))
        if contract_probe is not None:
            command.append("kotlinx.io.ApiContractProbeKt")
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
            "selected_source_function_ids": sorted(set(args.source_function_id)),
            "contract_probe": (environment["contract_probe"] if contract_probe else None),
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
