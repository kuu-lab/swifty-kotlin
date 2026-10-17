#!/usr/bin/env python3
"""Verify the SystemTemporaryDirectory JVM ABI and native consumer behavior."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from urllib.request import urlopen


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PROBES = HERE / "probes"
ROW_ID = "jvm-6dcae71c67e2278f"
CASE_ID = "local:Scripts/io_api_inventory/probe_system_temporary_directory.py#run_probe"
UPSTREAM_SOURCE_PATHS = (
    "core/api/kotlinx-io-core.api",
    "core/common/src/files/FileSystem.kt",
    "core/jvm/src/files/FileSystemJvm.kt",
    "core/apple/src/files/FileSystemApple.kt",
)
JVM_OWNER = "kotlinx.io.files.FileSystemJvmKt"
JVM_DESCRIPTOR = "Lkotlinx/io/files/Path;"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def tree_hash(path: Path) -> dict[str, str]:
    return {
        item.relative_to(path).as_posix(): sha256_file(item)
        for item in sorted(path.rglob("*"))
        if item.is_file()
    }


def required_tool(value: str | None, name: str) -> str:
    tool = value or shutil.which(name)
    if not tool:
        raise RuntimeError(f"required executable not found: {name}")
    return str(Path(tool).resolve())


def run_command(command: list[str], cwd: Path, stage: str, timeout: float,
                environment: dict[str, str] | None = None) -> dict:
    started = time.monotonic()
    result = subprocess.run(
        command,
        cwd=cwd,
        env={**os.environ, **(environment or {})},
        capture_output=True,
        timeout=timeout,
        check=False,
    )
    stdout_path = cwd / f"{stage}.stdout"
    stderr_path = cwd / f"{stage}.stderr"
    stdout_path.write_bytes(result.stdout)
    stderr_path.write_bytes(result.stderr)
    record = {
        "command": command,
        "exit_code": result.returncode,
        "seconds": time.monotonic() - started,
        "stdout_sha256": sha256_bytes(result.stdout),
        "stderr_sha256": sha256_bytes(result.stderr),
        "stdout": result.stdout.decode("utf-8", errors="replace"),
        "stderr": result.stderr.decode("utf-8", errors="replace"),
    }
    if result.returncode != 0:
        raise RuntimeError(f"{stage} exited with {result.returncode}; see {stdout_path} and {stderr_path}")
    return record


def download_pinned_artifact(url: str, destination: Path, expected_sha256: str) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_file() and sha256_file(destination) == expected_sha256:
        return destination
    with urlopen(url, timeout=60) as response:
        data = response.read()
    actual_sha256 = sha256_bytes(data)
    if actual_sha256 != expected_sha256:
        raise RuntimeError(f"pinned artifact hash mismatch for {destination.name}: {actual_sha256}")
    destination.write_bytes(data)
    return destination


def reference_artifacts(output: Path, core_jar_argument: Path | None,
                        stdlib_jar_argument: Path | None) -> tuple[Path, Path, dict]:
    artifact_lock = json.loads((HERE / "upstream-lock.json").read_text(encoding="utf-8"))
    reference_lock_path = ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json"
    reference_lock = json.loads(reference_lock_path.read_text(encoding="utf-8"))
    core_artifact = next(
        artifact for artifact in artifact_lock["mavenArtifacts"]
        if artifact["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1"
    )
    stdlib_file = next(entry for entry in reference_lock["sdk_files"] if entry["path"] == "lib/kotlin-stdlib.jar")
    kotlin_version = reference_lock["kotlin"]
    stdlib_url = (
        "https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-stdlib/"
        f"{kotlin_version}/kotlin-stdlib-{kotlin_version}.jar"
    )
    dependencies = output / "reference-dependencies"
    core_jar = core_jar_argument or dependencies / Path(core_artifact["url"]).name
    stdlib_jar = stdlib_jar_argument or dependencies / f"kotlin-stdlib-{kotlin_version}.jar"
    if core_jar_argument:
        if sha256_file(core_jar) != core_artifact["sha256"]:
            raise RuntimeError("provided kotlinx-io core jar does not match the pinned 0.9.1 artifact")
    else:
        core_jar = download_pinned_artifact(core_artifact["url"], core_jar, core_artifact["sha256"])
    if stdlib_jar_argument:
        if sha256_file(stdlib_jar) != stdlib_file["sha256"]:
            raise RuntimeError("provided Kotlin stdlib does not match the pinned 2.3.10 SDK")
    else:
        stdlib_jar = download_pinned_artifact(stdlib_url, stdlib_jar, stdlib_file["sha256"])
    return core_jar.resolve(), stdlib_jar.resolve(), {
        "kotlin_version": kotlin_version,
        "core_coordinate": core_artifact["coordinate"],
        "core_jar_sha256": sha256_file(core_jar),
        "stdlib_jar_sha256": sha256_file(stdlib_jar),
        "reference_lock_sha256": sha256_file(reference_lock_path),
    }


def upstream_source_hashes() -> dict[str, dict[str, str]]:
    lock = json.loads((HERE / "upstream-lock.json").read_text(encoding="utf-8"))
    locked_files = {entry["path"]: entry for entry in lock["upstreamFiles"]}
    results = {}
    upstream = HERE / "upstream/kotlinx-io-0.9.1"
    for relative in UPSTREAM_SOURCE_PATHS:
        path = upstream / relative
        data = path.read_bytes()
        expected = locked_files[relative]
        if len(data) != expected["size"] or sha256_bytes(data) != expected["sha256"]:
            raise RuntimeError(f"upstream source is not the pinned input: {relative}")
        results[relative] = {
            "git_blob_sha": expected["gitBlobSha"],
            "sha256": expected["sha256"],
        }
    return results


def load_inventory_row() -> dict:
    path = HERE / "api-inventory.tsv"
    with path.open(encoding="utf-8", newline="") as stream:
        rows = csv.DictReader(stream, delimiter="\t")
        matching = [row for row in rows if row["row_id"] == ROW_ID]
    if len(matching) != 1:
        raise RuntimeError(f"expected exactly one inventory row {ROW_ID}, found {len(matching)}")
    return matching[0]


def run_jvm_reference(output: Path, java: str, javac: str, javap: str,
                      core_jar: Path, stdlib_jar: Path, timeout: float) -> dict:
    reference = output / "jvm-reference"
    classes = reference / "classes"
    classes.mkdir(parents=True)
    javap_result = run_command(
        [javap, "-p", "-s", "-v", "-classpath", str(core_jar), JVM_OWNER],
        reference,
        "javap",
        timeout,
    )
    (reference / "javap.stdout").write_text(javap_result["stdout"], encoding="utf-8")
    javap_text = javap_result["stdout"]
    field_start = javap_text.find(" SystemTemporaryDirectory;")
    if field_start < 0:
        raise RuntimeError("javap did not expose SystemTemporaryDirectory as a field")
    field_block = javap_text[field_start:field_start + 500]
    required_javap = (
        "descriptor: " + JVM_DESCRIPTOR,
        "flags: (0x0019) ACC_PUBLIC, ACC_STATIC, ACC_FINAL",
    )
    if not all(value in field_block for value in required_javap):
        raise RuntimeError("javap field descriptor or public static final flags did not match")

    probe_source = PROBES / "SystemTemporaryDirectoryJvmProbe.java"
    compile_record = run_command(
        [javac, "--release", "8", "-d", str(classes), str(probe_source)],
        reference,
        "javac",
        timeout,
    )
    classpath = os.pathsep.join((str(classes), str(core_jar), str(stdlib_jar)))
    run_record = run_command(
        [java, "-cp", classpath, "SystemTemporaryDirectoryJvmProbe"],
        reference,
        "java",
        timeout,
    )
    expected_lines = (
        "JVM_OWNER:" + JVM_OWNER,
        "JVM_FIELD:SystemTemporaryDirectory",
        "JVM_DESCRIPTOR:" + JVM_DESCRIPTOR,
        "JVM_FLAGS:public,static,final",
        "JVM_VALUE_TYPE:kotlinx.io.files.Path",
        "JVM_VALUE_MATCHES_PROPERTY:true",
        "JVM_SAME_INSTANCE:true",
    )
    lines = run_record["stdout"].splitlines()
    if not all(value in lines for value in expected_lines):
        raise RuntimeError("JVM reflection probe output was incomplete or unexpected")
    return {
        "status": "PASS",
        "lane": "jvm-descriptor",
        "assertion_count": 9,
        "javap_stdout_sha256": javap_result["stdout_sha256"],
        "javac_stdout_sha256": compile_record["stdout_sha256"],
        "stdout_sha256": run_record["stdout_sha256"],
        "stdout": run_record["stdout"],
        "javap_field_excerpt": field_block.strip(),
    }


def native_temporary_directory(swift: str, output: Path, timeout: float) -> str:
    record = run_command(
        [swift, "-e", "import Foundation; print(NSTemporaryDirectory(), terminator: \"\")"],
        output,
        "foundation-reference",
        timeout,
    )
    raw = record["stdout"].rstrip("\n")
    while len(raw) > 1 and raw.endswith("/"):
        raw = raw[:-1]
    if not raw:
        raise RuntimeError("Foundation returned an empty NSTemporaryDirectory")
    return raw


def normalize_host_path(value: str, host_path: str) -> str:
    return value.replace(host_path, "<NSTemporaryDirectory>")


def run_candidate_lanes(output: Path, compiler: Path, package_root: Path, stdlib: Path,
                       foundation_temp: str, timeout: float) -> list[dict]:
    probe_source = PROBES / "system_temporary_directory.kt"
    results = []
    for route in ("source", "stdlib-library"):
        for optimization in ("O0", "O2"):
            lane = f"{route}-{optimization}"
            work = output / lane
            work.mkdir()
            temp = work / "tmp"
            temp.mkdir()
            environment = {
                "TMPDIR": str(temp) + os.sep,
                "KSWIFTK_STDLIB_CACHE_DIR": str(work / "stdlib-cache"),
                "KSWIFTK_PACKAGE_ROOT": str(package_root),
            }
            command = [str(compiler), "-" + optimization, "--no-incremental"]
            command += ["--stdlib-from-source"] if route == "source" else ["--stdlib-library", str(stdlib)]
            binary = work / "candidate"
            command += ["--entry-point", "main", str(probe_source), "-o", str(binary)]
            compile_record = run_command(command, work, "compile", timeout, environment)
            run_record = run_command([str(binary)], work, "run", timeout, environment)
            lines = run_record["stdout"].splitlines()
            expected_prefixes = (
                "KOTLIN_PROPERTY_TYPE:Path",
                "ERASED_IS_PATH:true",
                "KOTLIN_VALUES_EQUAL:true",
                "KOTLIN_SAME_INSTANCE:false",
            )
            if not all(value in lines for value in expected_prefixes):
                raise RuntimeError(f"{lane} did not satisfy the direct type/value/identity assertions")
            path_values = [line.removeprefix("KOTLIN_PATH_VALUE:") for line in lines
                           if line.startswith("KOTLIN_PATH_VALUE:")]
            if len(path_values) != 1 or path_values[0] != foundation_temp:
                raise RuntimeError(f"{lane} returned {path_values!r}, expected Foundation {foundation_temp!r}")
            normalized_stdout = normalize_host_path(run_record["stdout"], foundation_temp)
            result = {
                "status": "PASS",
                "lane": lane,
                "assertion_count": 6,
                "compile_stdout_sha256": compile_record["stdout_sha256"],
                "stdout_sha256": run_record["stdout_sha256"],
                "normalized_stdout_sha256": sha256_bytes(normalized_stdout.encode("utf-8")),
                "normalized_stdout": normalized_stdout,
            }
            results.append(result)
            print(f"PASS {lane} assertions=6", flush=True)
    return results


def write_validation_evidence(summary: dict) -> None:
    import generate

    path = HERE / "api-validation-evidence.json"
    evidence = json.loads(path.read_text(encoding="utf-8"))
    if evidence != {"schema_version": 2, "records": evidence.get("records")}:
        raise RuntimeError("validation evidence file has an unexpected schema")
    records = [record for record in evidence["records"] if record.get("row_id") != ROW_ID]
    candidate_sha = summary["candidate_sha"]
    reference_commit = summary["reference"]["upstream_commit"]
    case_spec = generate.LOCAL_PROBE_EVIDENCE_CASES[CASE_ID]
    executions = [{
        "case_id": CASE_ID,
        "lane": "jvm-descriptor",
        **{
            subject: {
                "execution_id": generate.local_probe_execution_id(
                    candidate_sha, reference_commit, CASE_ID, "jvm-descriptor", subject
                ),
                "result": "PASS",
                "exit_code": 0,
                "method": case_spec["methods"][subject],
            }
            for subject in ("reference", "candidate")
        },
    }]
    record = {
        "row_id": ROW_ID,
        "candidate_sha": candidate_sha,
        "reference_version": summary["reference"]["kotlinx_io_version"],
        "reference_commit": reference_commit,
        **summary["validation_input_hashes"],
        "compatibility_obligations": ["jvm-descriptor"],
        "executions": executions,
        "evidence_source": "local-probe",
    }
    records.append(record)
    evidence["records"] = sorted(records, key=lambda item: item["row_id"])
    path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    subprocess.run([sys.executable, str(HERE / "generate.py"), "--write"], cwd=ROOT, check=True)


def run_probe(arguments: argparse.Namespace) -> dict:
    if sys.platform != "darwin":
        raise RuntimeError("the candidate Apple temporary-directory probe requires macOS")
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    package_root = (arguments.package_root or ROOT).resolve()
    compiler_root = (arguments.compiler_root or package_root).resolve()
    compiler = arguments.compiler.resolve()
    if not compiler.is_file():
        raise RuntimeError(f"compiler not found: {compiler}; run swift build first")
    if not compiler.is_relative_to(compiler_root):
        raise RuntimeError(f"compiler must be inside its source checkout: {compiler_root}")
    candidate_sha = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=package_root, capture_output=True, text=True, check=True
    ).stdout.strip()
    compiler_sha = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=compiler_root, capture_output=True, text=True, check=True
    ).stdout.strip()
    if compiler_sha != candidate_sha:
        raise RuntimeError(
            f"compiler checkout is {compiler_sha}, candidate package root is {candidate_sha}"
        )
    if (arguments.expected_candidate_sha
            and candidate_sha != arguments.expected_candidate_sha):
        raise RuntimeError(
            f"candidate checkout is {candidate_sha}, expected {arguments.expected_candidate_sha}"
        )
    java = required_tool(arguments.java, "java")
    javac = required_tool(arguments.javac, "javac")
    javap = required_tool(arguments.javap, "javap")
    swift = required_tool(arguments.swift, "swift")
    timeout = arguments.timeout

    import generate

    reference_lock = json.loads((ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json").read_text(encoding="utf-8"))
    upstream_lock = json.loads((HERE / "upstream-lock.json").read_text(encoding="utf-8"))
    core_jar, stdlib_jar, artifact_summary = reference_artifacts(
        output, arguments.core_jar, arguments.kotlin_stdlib_jar
    )
    foundation_temp = native_temporary_directory(swift, output, timeout)
    stdlib_artifact = output / "fresh-KSwiftKStdlib.kklib"
    stdlib_result = run_command(
        [str(compiler), "--stdlib-only", "--no-incremental", "-o", str(stdlib_artifact)],
        output,
        "stdlib-build",
        timeout,
        {"KSWIFTK_PACKAGE_ROOT": str(package_root), "KSWIFTK_STDLIB_CACHE_DIR": str(output / "stdlib-cache")},
    )
    if (not (stdlib_artifact / "metadata.bin").is_file()
            or not any((stdlib_artifact / "objects").glob("*"))):
        raise RuntimeError("fresh stdlib build did not produce a metadata and object-bearing KLIB")

    reference_result = run_jvm_reference(output, java, javac, javap, core_jar, stdlib_jar, timeout)
    for relative in (
        "Sources/CompilerCore/Stdlib/kotlinx/io/files/Paths.kt",
        "Sources/Runtime/RuntimeIoFileSystem.swift",
    ):
        if sha256_file(package_root / relative) != sha256_file(ROOT / relative):
            raise RuntimeError(f"pinned candidate implementation input differs from the ledger: {relative}")
    candidate_results = run_candidate_lanes(
        output, compiler, package_root, stdlib_artifact, foundation_temp, timeout
    )
    row = load_inventory_row()
    input_hashes = generate.validation_input_hashes(row, ROOT, generate.UPSTREAM)
    upstream_sources = upstream_source_hashes()
    stdlib_files = tree_hash(stdlib_artifact)
    stdlib_manifest_bytes = json.dumps(
        stdlib_files, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    (output / "fresh-stdlib-file-hashes.json").write_text(
        json.dumps(stdlib_files, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    local_probe_hashes = {
        path.relative_to(ROOT).as_posix(): sha256_file(path)
        for path in (
            Path(__file__).resolve(),
            PROBES / "system_temporary_directory.kt",
            PROBES / "SystemTemporaryDirectoryJvmProbe.java",
            HERE / "generate.py",
            HERE / "test_validation_evidence.py",
            HERE / "upstream-lock.json",
            ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json",
        )
    }
    summary = {
        "schema_version": 1,
        "row_id": ROW_ID,
        "case_id": CASE_ID,
        "candidate_sha": candidate_sha,
        "candidate_package_root": str(package_root),
        "compiler_source_root": str(compiler_root),
        "status": "PASS",
        "reference": {
            "kotlin_version": artifact_summary["kotlin_version"],
            "kotlinx_io_version": upstream_lock["tag"],
            "upstream_commit": upstream_lock["commit"],
            "upstream_sources": upstream_sources,
            "artifacts": artifact_summary,
            "result": reference_result,
        },
        "candidate": {
            "host": "macOS Foundation NSTemporaryDirectory",
            "fresh_stdlib_kklib": {
                "file_count": len(stdlib_files),
                "file_hash_manifest_sha256": sha256_bytes(stdlib_manifest_bytes),
            },
            "stdlib_build_stdout_sha256": stdlib_result["stdout_sha256"],
            "expected_temporary_directory": "<NSTemporaryDirectory>",
            "lanes": candidate_results,
        },
        "local_probe_sha256": local_probe_hashes,
        "validation_input_hashes": input_hashes,
        "execution_count": 5,
        "assertion_count": reference_result["assertion_count"] + sum(
            result["assertion_count"] for result in candidate_results
        ),
    }
    summary_path = output / "summary.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if arguments.write_evidence:
        write_validation_evidence(summary)
        summary["validation_evidence_written"] = True
        summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=ROOT / ".build/debug/kswiftc")
    parser.add_argument("--package-root", type=Path,
                        help="candidate source checkout (defaults to this worktree)")
    parser.add_argument("--compiler-root", type=Path,
                        help="checkout used to build --compiler (defaults to --package-root)")
    parser.add_argument("--expected-candidate-sha",
                        help="fail unless the candidate checkout is at this commit")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--core-jar", type=Path, help="use a provided core 0.9.1 jar after hash verification")
    parser.add_argument("--kotlin-stdlib-jar", type=Path, help="use a provided Kotlin 2.3.10 stdlib after hash verification")
    parser.add_argument("--java")
    parser.add_argument("--javac")
    parser.add_argument("--javap")
    parser.add_argument("--swift")
    parser.add_argument("--timeout", type=float, default=1800)
    parser.add_argument("--write-evidence", action="store_true")
    arguments = parser.parse_args()
    try:
        run_probe(arguments)
        return 0
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
