#!/usr/bin/env python3
"""Run ByteString backing-array identity probes with the pinned macOS Native compiler."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LOCK_PATH = ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json"
REFERENCE_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"
PROBE_DIR = ROOT / "Scripts/io_api_inventory/bytestring_backing_array"
PROBE_SOURCES = [
    PROBE_DIR / "Probe.kt",
    PROBE_DIR / "Producer.kt",
    PROBE_DIR / "Consumer.kt",
]
EXPECTED_OUTPUT = b"PASS:direct=true:inline=true:repeat=true\n"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha(path: Path) -> str:
    return digest(path.read_bytes())


def save(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run(command: list[str], directory: Path, name: str, timeout: float,
        environment: dict[str, str]) -> dict:
    try:
        result = subprocess.run(command, cwd=directory, env={**os.environ, **environment},
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False)
        exit_code = result.returncode
        stdout, stderr = result.stdout, result.stderr
        status = "PASS" if exit_code == 0 else "FAIL"
    except subprocess.TimeoutExpired as error:
        exit_code = 124
        stdout = error.stdout or b""
        stderr = (error.stderr or b"") + f"\nTIMEOUT after {timeout}s\n".encode()
        status = "TIMEOUT"
    (directory / f"{name}.stdout").write_bytes(stdout)
    (directory / f"{name}.stderr").write_bytes(stderr)
    receipt = {
        "command": command,
        "cwd": str(directory),
        "result": status,
        "exit_code": exit_code,
        "stdout_sha256": digest(stdout),
        "stderr_sha256": digest(stderr),
    }
    save(directory / f"{name}.json", receipt)
    return receipt


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference-root", type=Path, required=True,
                        help="output directory from prepare_reference.py --target macos_arm64")
    parser.add_argument("--output", type=Path, required=True, help="new output directory")
    parser.add_argument("--konan-data", type=Path,
                        help="persistent Kotlin/Native dependency cache; defaults to <reference-root>/konan-data")
    parser.add_argument("--compile-timeout", type=float, default=600)
    args = parser.parse_args(argv)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    if sys.platform != "darwin" or platform.machine() != "arm64":
        parser.error("the pinned macos_arm64 reference requires an Apple Silicon macOS host")

    reference_root = args.reference_root.resolve()
    paths = json.loads((reference_root / "paths.json").read_text(encoding="utf-8"))
    lock_bytes = LOCK_PATH.read_bytes()
    lock = json.loads(lock_bytes)
    if paths.get("target") != "macos_arm64":
        parser.error("reference root must be prepared for target macos_arm64")
    if paths.get("reference_lock_sha256") != digest(lock_bytes) or lock.get("commit") != REFERENCE_COMMIT:
        parser.error("reference root does not match the pinned kotlinx-io reference lock")

    dependencies = Path(paths["dependencies"])
    compiler = Path(paths["installation"]) / "bin/kotlinc-native"
    native_artifacts = {
        artifact["coordinate"].split(":")[1]: artifact
        for artifact in lock["native_artifacts"]
        if artifact["coordinate"].endswith(":0.9.1")
        and "macosarm64" in artifact["coordinate"]
    }
    core_name = "kotlinx-io-core-macosarm64"
    bytestring_name = "kotlinx-io-bytestring-macosarm64"
    core = dependencies / f"{core_name}-0.9.1.klib"
    bytestring = dependencies / f"{bytestring_name}-0.9.1.klib"
    if file_sha(core) != native_artifacts[core_name]["sha256"] or file_sha(bytestring) != native_artifacts[bytestring_name]["sha256"]:
        parser.error("pinned macOS Native kotlinx-io KLIB hash mismatch")
    compiler_archive = Path(paths["compiler_archive"])
    if file_sha(compiler_archive) != paths["compiler_archive_sha256"]:
        parser.error("pinned Kotlin/Native compiler archive hash mismatch")

    java = shutil.which("java")
    if not java:
        parser.error("Java executable is required by the pinned Kotlin/Native compiler")
    java_home = str(Path(java).resolve().parent.parent)
    konan_data = (args.konan_data or (reference_root / "konan-data")).resolve()
    konan_data.mkdir(parents=True, exist_ok=True)
    environment = {"JAVA_HOME": java_home, "KONAN_DATA_DIR": str(konan_data)}
    executions = []
    summary = {
        "schema_version": 1,
        "reference_version": "2.3.10",
        "reference_commit": REFERENCE_COMMIT,
        "target": "macos_arm64",
        "compiler_archive_sha256": paths["compiler_archive_sha256"],
        "compiler_sha256": file_sha(compiler),
        "dependencies_sha256": {core.name: file_sha(core), bytestring.name: file_sha(bytestring)},
        "probe_sources_sha256": {path.name: file_sha(path) for path in PROBE_SOURCES},
        "expected_output": EXPECTED_OUTPUT.decode(),
        "expected_output_sha256": digest(EXPECTED_OUTPUT),
        "optimizations": {},
    }

    for optimization in ("O0", "O2"):
        lane = output / f"apple-{optimization}"
        lane.mkdir()
        executable = lane / "bytestring-backing-array.kexe"
        command = [
            str(compiler),
            "-target", "macos_arm64",
            "-friend-modules", str(bytestring),
            "-library", str(core),
            "-library", str(bytestring),
            "-entry", "kotlinx.io.bytestring.probe.consumer.main",
        ]
        if optimization == "O2":
            command.append("-opt")
        command += ["-o", str(executable), *map(str, PROBE_SOURCES)]
        compile_receipt = run(command, lane, "compile", args.compile_timeout, environment)
        run_receipt = None
        if compile_receipt["result"] == "PASS":
            run_receipt = run([str(executable)], lane, "run", 30, environment)
            stdout = (lane / "run.stdout").read_bytes()
            if run_receipt["result"] != "PASS" or stdout != EXPECTED_OUTPUT or (lane / "run.stderr").read_bytes():
                run_receipt["result"] = "FAIL"
                run_receipt["exit_code"] = run_receipt["exit_code"] or 1
                save(lane / "run.json", run_receipt)
        summary["optimizations"][optimization] = {
            "compile": compile_receipt,
            "run": run_receipt,
            "stdout_sha256": file_sha(lane / "run.stdout") if (lane / "run.stdout").is_file() else None,
            "stderr_sha256": file_sha(lane / "run.stderr") if (lane / "run.stderr").is_file() else None,
        }
        if run_receipt is not None:
            executions.append({
                "execution_id": f"bytestring-backing-array:apple-reference:{optimization}",
                "case_id": "Scripts/io_api_inventory/bytestring_backing_array/Probe.kt#directBackingArrayIdentity",
                "lane": f"apple-native-{optimization}",
                "side": "reference",
                "result": run_receipt["result"],
                "exit_code": run_receipt["exit_code"],
                "stdout_sha256": run_receipt["stdout_sha256"],
                "stderr_sha256": run_receipt["stderr_sha256"],
            })

    summary["status"] = (
        "PASS"
        if all(summary["optimizations"][level]["run"]
               and summary["optimizations"][level]["run"]["result"] == "PASS"
               for level in ("O0", "O2"))
        else "FAILED_OR_INCOMPLETE"
    )
    save(output / "summary.json", summary)
    save(output / "execution-records.json", {"schema_version": 1, "executions": executions})
    print(summary["status"])
    return 0 if summary["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
