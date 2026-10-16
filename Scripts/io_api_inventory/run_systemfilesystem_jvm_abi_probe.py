#!/usr/bin/env python3
"""Inspect the pinned kotlinx-io JVM field and retain a compact receipt."""
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
PROBE = HERE / "probes/systemfilesystem/SystemFileSystemJvmAbiProbe.java"
CASE_ID = "Scripts/io_api_inventory/probes/systemfilesystem/SystemFileSystemJvmAbiProbe.java#main"
EXPECTED_LINES = [
    "SystemFileSystemJvmAbiProbe:owner=kotlinx.io.files.FileSystemJvmKt",
    "SystemFileSystemJvmAbiProbe:descriptor=Lkotlinx/io/files/FileSystem;",
    "SystemFileSystemJvmAbiProbe:flags=public static final",
    "SystemFileSystemJvmAbiProbe:value-type=FileSystem",
    "SystemFileSystemJvmAbiProbe:identity=stable",
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
    parser.add_argument("--core-jar", type=Path, required=True, help="locked kotlinx-io-core-jvm-0.9.1.jar")
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
    stdlib = kotlin_home / "lib/kotlin-stdlib.jar"
    core_jar = args.core_jar.resolve()
    if not java.is_file() or not javac.is_file() or not stdlib.is_file() or not core_jar.is_file():
        raise RuntimeError("Java, javac, the Kotlin standard library, and the locked IO jar are required")
    version = subprocess.run([str(java), "-version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    version_text = (version.stdout + version.stderr).decode("utf-8", errors="replace")
    if version.returncode != 0 or not re.search(r'version "21[.\"]', version_text):
        raise RuntimeError("the JVM field probe requires Java 21")
    (output / "java-version.stdout").write_bytes(version.stdout)
    (output / "java-version.stderr").write_bytes(version.stderr)

    api_lock = json.loads((REPO / "Scripts/kotlinx_io_upstream/reference-lock.json").read_text(encoding="utf-8"))
    if (api_lock.get("kotlinx_io"), api_lock.get("commit")) != (
        "0.9.1", "362bdc35e159bad6da1e08101c8321792d762281"
    ):
        raise RuntimeError("the JVM probe reference is not pinned to kotlinx-io 0.9.1")
    core_records = [
        record for record in api_lock.get("jvm_artifacts", [])
        if record.get("coordinate") == "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1"
    ]
    if len(core_records) != 1 or sha256(core_jar) != core_records[0].get("sha256"):
        raise RuntimeError("the JVM probe jar does not match the locked kotlinx-io core artifact")

    sdk_lock = json.loads((REPO / "Scripts/kotlinx_io_upstream/reference-lock.json").read_text(encoding="utf-8"))
    stdlib_records = [record for record in sdk_lock.get("sdk_files", []) if record.get("path") == "lib/kotlin-stdlib.jar"]
    if len(stdlib_records) != 1 or sha256(stdlib) != stdlib_records[0].get("sha256"):
        raise RuntimeError("the Kotlin runtime does not match the locked 2.3.10 SDK")

    classes = output / "classes"
    classes.mkdir()
    run([str(javac), "-d", str(classes), str(PROBE)], output, output / "javac.stdout", output / "javac.stderr")
    classpath = os.pathsep.join((str(classes), str(core_jar), str(stdlib)))
    run([str(java), "-cp", classpath, "SystemFileSystemJvmAbiProbe"], output,
        output / "probe.stdout", output / "probe.stderr")
    observed = (output / "probe.stdout").read_text(encoding="utf-8").splitlines()
    if observed != EXPECTED_LINES:
        raise RuntimeError("JVM field probe output differed from the direct ABI assertions")

    receipt = {
        "schema_version": 1,
        "case_id": CASE_ID,
        "candidate_sha": args.candidate_sha,
        "reference_version": api_lock["kotlinx_io"],
        "reference_commit": api_lock["commit"],
        "reference_artifact_sha256": sha256(core_jar),
        "probe_input_sha256": sha256(PROBE),
        "reference_only": True,
        "candidate_jvm_emission": "not-applicable: KSwiftK Native backend does not emit JVM classfiles",
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
