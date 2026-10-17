#!/usr/bin/env python3
"""Inspect the pinned kotlinx-io JVM field and retain a reference-only receipt."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PROBE = HERE / "probes/systempathseparator/SystemPathSeparatorJvmAbiProbe.java"
CASE_ID = "Scripts/io_api_inventory/probes/systempathseparator/SystemPathSeparatorJvmAbiProbe.java#main"
JVM_NATIVE_EMISSION_NOT_APPLICABLE = "KSwiftK Native backend does not emit JVM classfiles"
EXPECTED_LINES = [
    "SystemPathSeparatorJvmAbiProbe:owner=kotlinx.io.files.PathsJvmKt",
    "SystemPathSeparatorJvmAbiProbe:descriptor=C",
    "SystemPathSeparatorJvmAbiProbe:flags=public static final",
    "SystemPathSeparatorJvmAbiProbe:type=char",
    f"SystemPathSeparatorJvmAbiProbe:value={os.sep}",
    "SystemPathSeparatorJvmAbiProbe:getter-absent=true",
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], cwd: Path, stdout_path: Path, stderr_path: Path) -> None:
    result = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    stdout_path.write_bytes(result.stdout)
    stderr_path.write_bytes(result.stderr)
    if result.returncode != 0:
        raise RuntimeError(f"command exited {result.returncode}: {' '.join(command)}")
    if result.stderr:
        raise RuntimeError(f"command wrote stderr: {stderr_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--java", type=Path, required=True, help="Java 21 executable")
    parser.add_argument("--kotlin-home", type=Path, required=True, help="locked Kotlin 2.3.10 SDK root")
    parser.add_argument("--dependencies", type=Path, required=True, help="directory containing the locked IO JVM jars")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--candidate-sha", required=True, help="candidate commit whose source consumer was tested")
    args = parser.parse_args()
    if not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", args.candidate_sha):
        parser.error("candidate SHA must be a full lowercase Git SHA")

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    java = args.java.resolve()
    javac = java.with_name("javac")
    kotlin_home = args.kotlin_home.resolve()
    core_jar = (args.dependencies / "kotlinx-io-core-jvm-0.9.1.jar").resolve()
    bytestring_jar = (args.dependencies / "kotlinx-io-bytestring-jvm-0.9.1.jar").resolve()
    stdlib = kotlin_home / "lib/kotlin-stdlib.jar"
    if not all(path.is_file() for path in (java, javac, core_jar, bytestring_jar, stdlib)):
        raise RuntimeError("Java, javac, the locked Kotlin runtime, and the locked IO jars are required")

    version = subprocess.run([str(java), "-version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    version_text = (version.stdout + version.stderr).decode("utf-8", errors="replace")
    if version.returncode != 0 or not re.search(r'version "21[.\"]', version_text):
        raise RuntimeError("the JVM field probe requires Java 21")
    (output / "java-version.stdout").write_bytes(version.stdout)
    (output / "java-version.stderr").write_bytes(version.stderr)

    reference_lock = json.loads((REPO / "Scripts/kotlinx_io_upstream/reference-lock.json").read_text(encoding="utf-8"))
    if (reference_lock.get("kotlinx_io"), reference_lock.get("commit")) != (
        "0.9.1", "362bdc35e159bad6da1e08101c8321792d762281"
    ):
        raise RuntimeError("the JVM probe reference is not pinned to kotlinx-io 0.9.1")
    locked_artifacts = {record["url"].rsplit("/", 1)[1]: record for record in reference_lock["jvm_artifacts"]}
    for artifact in (core_jar, bytestring_jar):
        record = locked_artifacts.get(artifact.name)
        if not record or sha256(artifact) != record.get("sha256"):
            raise RuntimeError(f"the JVM probe jar does not match the lock: {artifact.name}")
    locked_stdlib = [record for record in reference_lock["sdk_files"] if record.get("path") == "lib/kotlin-stdlib.jar"]
    if len(locked_stdlib) != 1 or sha256(stdlib) != locked_stdlib[0].get("sha256"):
        raise RuntimeError("the Kotlin runtime does not match the locked 2.3.10 SDK")

    classes = output / "classes"
    classes.mkdir()
    run([str(javac), "-d", str(classes), str(PROBE)], output,
        output / "javac.stdout", output / "javac.stderr")
    classpath = os.pathsep.join(map(str, (classes, core_jar, bytestring_jar, stdlib)))
    run([str(java), "-cp", classpath, "SystemPathSeparatorJvmAbiProbe"], output,
        output / "probe.stdout", output / "probe.stderr")
    stdout = (output / "probe.stdout").read_bytes()
    stderr = (output / "probe.stderr").read_bytes()
    if stderr or stdout.decode("utf-8").splitlines() != EXPECTED_LINES:
        raise RuntimeError("JVM field probe output differed from the direct ABI assertions")

    receipt = {
        "schema_version": 1,
        "case_id": CASE_ID,
        "candidate_sha": args.candidate_sha,
        "reference_version": reference_lock["kotlinx_io"],
        "reference_commit": reference_lock["commit"],
        "reference_artifact_sha256": sha256(core_jar),
        "probe_input_sha256": sha256(PROBE),
        "reference_only": True,
        "candidate_jvm_emission": f"not-applicable: {JVM_NATIVE_EMISSION_NOT_APPLICABLE}",
        "java_version_sha256": hashlib.sha256(version_text.encode("utf-8")).hexdigest(),
        "result": "PASS",
        "exit_code": 0,
        "stdout_sha256": sha256(output / "probe.stdout"),
        "normalized_stdout_sha256": sha256(output / "probe.stdout"),
        "stderr_sha256": sha256(output / "probe.stderr"),
    }
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
