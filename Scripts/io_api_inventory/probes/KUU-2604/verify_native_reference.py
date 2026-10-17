#!/usr/bin/env python3
"""Run Buffer.hintEmit against the hash-locked kotlinx-io macOS Native KLIB."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import signal
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
FIXTURE = ROOT / "Tests/CompilerBackendTests/Fixtures/IOBufferHintEmit2604"
UPSTREAM_RUNNER = ROOT / "Scripts/kotlinx_io_upstream"
REFERENCE_LOCK = UPSTREAM_RUNNER / "reference-lock.json"
sys.path.insert(0, str(UPSTREAM_RUNNER))
from run_native_reference import dependency_fingerprint, verify_native_sdk


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_digest(path: Path) -> str:
    return digest(path.read_bytes())


def command_digest(commands: list[list[str]]) -> str:
    encoded = json.dumps(commands, ensure_ascii=False, separators=(",", ":")).encode()
    return digest(encoded)


def execute(command: list[str], output: Path, name: str, environment: dict[str, str], timeout: float) -> dict:
    started = time.monotonic()
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env={**os.environ, **environment}, start_new_session=True)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            stdout, stderr = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            stdout, stderr = process.communicate()
    result = {
        "command": command,
        "command_sha256": command_digest([command]),
        "exit_code": 124 if timed_out else process.returncode,
        "timed_out": timed_out,
        "stdout": stdout,
        "stdout_sha256": digest(stdout),
        "stderr": stderr,
        "stderr_sha256": digest(stderr),
        "seconds": time.monotonic() - started,
    }
    (output / f"{name}.stdout").write_bytes(stdout)
    (output / f"{name}.stderr").write_bytes(stderr)
    (output / f"{name}.command.json").write_text(json.dumps({
        "command": command,
        "command_sha256": result["command_sha256"],
        "exit_code": result["exit_code"],
        "timed_out": timed_out,
        "stdout_sha256": result["stdout_sha256"],
        "stderr_sha256": result["stderr_sha256"],
        "seconds": result["seconds"],
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=("macos_arm64", "macos_x64"), required=True)
    parser.add_argument("--kotlin-home", type=Path, required=True)
    parser.add_argument("--compiler-archive", type=Path, required=True)
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--konan-data", type=Path, required=True)
    parser.add_argument("--expected", type=Path, required=True,
                        help="byte-exact output from the pinned Kotlin/JVM reference consumer")
    parser.add_argument("--candidate-sha", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compile-timeout", type=float, default=900)
    parser.add_argument("--run-timeout", type=float, default=60)
    args = parser.parse_args()

    if (not math.isfinite(args.compile_timeout) or args.compile_timeout <= 0
            or not math.isfinite(args.run_timeout) or args.run_timeout <= 0):
        parser.error("timeouts must be finite positive numbers")
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", args.candidate_sha):
        parser.error("candidate SHA must be a full lowercase Git SHA")
    expected_host = ("Darwin", "arm64") if args.target == "macos_arm64" else ("Darwin", "x86_64")
    if (platform.system(), platform.machine()) != expected_host:
        raise RuntimeError(f"Native reference must execute on {expected_host}, got {(platform.system(), platform.machine())}")

    lock = json.loads(REFERENCE_LOCK.read_text(encoding="utf-8"))
    if (lock.get("kotlin"), lock.get("kotlinx_io"), lock.get("commit")) != (
        "2.3.10", "0.9.1", "362bdc35e159bad6da1e08101c8321792d762281"
    ):
        raise RuntimeError("Native reference lock does not match the issue pin")
    archive_record = lock["native_compiler_archives"][args.target]
    sdk = verify_native_sdk(args.kotlin_home.resolve(), args.compiler_archive.resolve(), archive_record)
    artifacts = [item for item in lock["native_artifacts"]
                 if args.target.replace("_", "") in item["coordinate"]]
    libraries = []
    for artifact in artifacts:
        path = args.dependencies.resolve() / artifact["url"].rsplit("/", 1)[-1]
        if not path.is_file() or file_digest(path) != artifact["sha256"]:
            raise RuntimeError(f"pinned Native artifact missing or hash mismatch: {path.name}")
        libraries.append(path)

    kotlin_home = args.kotlin_home.resolve()
    compiler = kotlin_home / "bin/konanc"
    java = args.java.resolve()
    if not compiler.is_file() or not java.is_file():
        raise RuntimeError("Kotlin/Native compiler and Java executable must exist")
    javac = java.with_name("javac")
    if not javac.is_file():
        raise RuntimeError("the supplied Java 21 installation must include javac")

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    temporary = output / "tmp"
    temporary.mkdir()
    args.konan_data.mkdir(parents=True, exist_ok=True)
    environment = {
        "KONAN_DATA_DIR": str(args.konan_data.resolve()),
        "TMPDIR": str(temporary) + "/",
        "JAVA_HOME": str(java.parent.parent),
        "JAVACMD": str(java),
    }

    java_version = execute([str(java), "-version"], output, "java-version", environment, 30)
    java_text = (java_version["stdout"] + java_version["stderr"]).decode("utf-8", "replace")
    if java_version["exit_code"] != 0 or not re.search(r'version "21[.\"]', java_text):
        raise RuntimeError("Native reference requires Java 21")
    version = execute([str(compiler), "-version"], output, "kotlin-version", environment, 30)
    version_text = (version["stdout"] + version["stderr"]).decode("utf-8", "replace")
    if version["exit_code"] != 0 or not re.search(r"(?:Kotlin/Native|kotlinc-native)\s+2\.3\.10(?:\s|$)", version_text):
        raise RuntimeError("Native reference requires Kotlin/Native 2.3.10")
    xcode = execute(["xcodebuild", "-version"], output, "xcode-version", environment, 30)
    sdk_version = execute(["xcrun", "--sdk", "macosx", "--show-sdk-version"],
                          output, "macos-sdk-version", environment, 30)
    sdk_path = execute(["xcrun", "--sdk", "macosx", "--show-sdk-path"],
                       output, "macos-sdk-path", environment, 30)
    if any(result["exit_code"] != 0 for result in (xcode, sdk_version, sdk_path)):
        raise RuntimeError("Xcode and the macOS SDK are required for the Native reference")

    program = output / "buffer-hint-emit.kexe"
    compile_command = [str(compiler), "-target", args.target]
    for library in libraries:
        compile_command += ["-library", str(library)]
    compile_command += ["-entry", "kuu2604.main",
                        str(FIXTURE / "BufferHintEmitProducer.kt"),
                        str(FIXTURE / "BufferHintEmitConsumer.kt"), "-o", str(program)]
    compile_result = execute(compile_command, output, "consumer-compile", environment, args.compile_timeout)
    if compile_result["exit_code"] != 0:
        raise RuntimeError("pinned Native consumer failed to compile: " + compile_result["stderr"].decode("utf-8", "replace"))

    run_result = execute([str(program)], output, "consumer-run", environment, args.run_timeout)
    expected = args.expected.read_bytes()
    if run_result["exit_code"] != 0 or run_result["stderr"] or run_result["stdout"] != expected:
        raise RuntimeError("pinned Native consumer output differs from the JVM reference")

    negative_program = output / "negative.kexe"
    negative_command = [str(compiler), "-target", args.target]
    for library in libraries:
        negative_command += ["-library", str(library)]
    negative_command += [str(FIXTURE / "BufferHintEmitNegativeOptIn.kt"), "-o", str(negative_program)]
    negative = execute(negative_command, output, "negative-compile", environment, args.compile_timeout)
    negative_diagnostic = negative["stdout"] + negative["stderr"]
    if (negative["exit_code"] == 0
            or b"hintEmit" not in negative_diagnostic
            or b"internal api" not in negative_diagnostic.lower()):
        raise RuntimeError("pinned Native negative consumer did not reject Buffer.hintEmit without opt-in")

    receipt = {
        "reference_version": lock["kotlinx_io"],
        "kotlin_version": lock["kotlin"],
        "reference_commit": lock["commit"],
        "reference_lock_sha256": file_digest(REFERENCE_LOCK),
        "target": args.target,
        "candidate_sha": args.candidate_sha,
        "compiler_archive_sha256": archive_record["sha256"],
        "compiler_sdk": sdk,
        "compiler_sha256": file_digest(compiler),
        "java_sha256": file_digest(java),
        "xcode_version_sha256": xcode["stdout_sha256"],
        "macos_sdk_version_sha256": sdk_version["stdout_sha256"],
        "macos_sdk_path_sha256": sdk_path["stdout_sha256"],
        "toolchain_dependencies": dependency_fingerprint(args.konan_data.resolve() / "dependencies"),
        "native_artifacts": [
            {"coordinate": artifact["coordinate"], "sha256": artifact["sha256"],
             "path": path.name}
        for artifact, path in zip(artifacts, libraries)
        ],
        "expected_stdout_sha256": digest(expected),
        "reference": {
            "result": "PASS",
            "command_sha256": command_digest([compile_command, [str(program)]]),
            "exit_code": run_result["exit_code"],
            "stdout_sha256": run_result["stdout_sha256"],
            "stdout_bytes": len(run_result["stdout"]),
            "stderr_sha256": digest(compile_result["stderr"] + run_result["stderr"]),
            "stderr_bytes": len(compile_result["stderr"] + run_result["stderr"]),
        },
        "negative_opt_in": {
            "result": "PASS",
            "command_sha256": negative["command_sha256"],
            "exit_code": negative["exit_code"],
            "diagnostic_sha256": digest(negative_diagnostic),
            "diagnostic_bytes": len(negative_diagnostic),
            "rejects_without_opt_in": True,
            "diagnostic_mentions_marker": b"InternalIoApi" in negative_diagnostic,
        },
    }
    receipt_path = output / "receipt.json"
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "status": "PASS",
        "receipt": str(receipt_path),
        "candidate_sha": args.candidate_sha,
        "target": args.target,
        "stdout_sha256": run_result["stdout_sha256"],
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
