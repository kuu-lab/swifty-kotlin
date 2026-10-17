#!/usr/bin/env python3
"""Check the pinned JVM descriptor and the candidate's imported KLIB opt-in."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
FIXTURE = ROOT / "Tests/CompilerBackendTests/Fixtures/IOBufferHintEmit2604"
REFERENCE_LOCK = ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_digest(path: Path) -> str:
    return digest(path.read_bytes())


def command_digest(command: list[str]) -> str:
    encoded = json.dumps(command, ensure_ascii=False, separators=(",", ":")).encode()
    return digest(encoded)


def run(command: list[str], *, env: dict[str, str] | None = None) -> dict:
    process = subprocess.run(command, capture_output=True, env=env)
    return {
        "command": command,
        "command_sha256": command_digest(command),
        "exit_code": process.returncode,
        "stdout": process.stdout,
        "stdout_sha256": digest(process.stdout),
        "stderr": process.stderr,
        "stderr_sha256": digest(process.stderr),
    }


def reference_jar(dependencies: Path, lock: dict) -> tuple[Path, dict]:
    artifact = next(
        item for item in lock["jvm_artifacts"]
        if item["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1"
    )
    jar = dependencies / artifact["url"].rsplit("/", 1)[-1]
    if not jar.is_file() or file_digest(jar) != artifact["sha256"]:
        raise RuntimeError("pinned kotlinx-io-core-jvm 0.9.1 jar is missing or has the wrong hash")
    return jar, artifact


def inspect_jvm_descriptor(javap: Path, jar: Path) -> dict:
    command = [str(javap), "-classpath", str(jar), "-p", "-s", "-v", "kotlinx.io.Buffer"]
    result = run(command)
    if result["exit_code"] != 0 or result["stderr"]:
        raise RuntimeError("javap failed: " + result["stderr"].decode("utf-8", "replace"))
    text = result["stdout"].decode("utf-8", "replace")
    lines = text.splitlines()
    declarations = [index for index, line in enumerate(lines)
                    if re.fullmatch(r"\s+public void hintEmit\(\);", line)]
    if len(declarations) != 1:
        raise RuntimeError(f"expected one public Buffer.hintEmit() JVM method, found {len(declarations)}")
    start = declarations[0]
    end = next((index for index in range(start + 1, len(lines))
                if re.match(r"\s{2}(?:public|protected|private)\s", lines[index])), len(lines))
    block = "\n".join(lines[start:end])
    if not re.search(r"^\s+descriptor: \(\)V$", block, re.MULTILINE):
        raise RuntimeError("Buffer.hintEmit() must have the JVM descriptor ()V")
    if "ACC_PUBLIC" not in block:
        raise RuntimeError("Buffer.hintEmit() must be public")
    if "RuntimeInvisibleAnnotations:" not in block or "kotlinx.io.InternalIoApi" not in block:
        raise RuntimeError("Buffer.hintEmit() must retain the InternalIoApi JVM annotation")
    if any("hintEmit$default" in line for line in lines):
        raise RuntimeError("zero-argument Buffer.hintEmit() must not have a default-argument bridge")
    return {
        "command": result["command"],
        "command_sha256": result["command_sha256"],
        "exit_code": result["exit_code"],
        "stdout": result["stdout"],
        "stdout_sha256": result["stdout_sha256"],
        "stderr_sha256": result["stderr_sha256"],
        "class": "kotlinx.io.Buffer",
        "method_count": len(declarations),
        "descriptor": "()V",
        "visibility": "public",
        "internal_io_api": True,
        "default_bridge": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--stdlib-library", type=Path, required=True)
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--expected", type=Path, required=True)
    parser.add_argument("--candidate-sha", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    candidate_sha = args.candidate_sha
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", candidate_sha):
        parser.error("candidate SHA must be a full lowercase Git SHA")
    lock = json.loads(REFERENCE_LOCK.read_text(encoding="utf-8"))
    if (lock.get("kotlin"), lock.get("kotlinx_io"), lock.get("commit")) != (
        "2.3.10", "0.9.1", "362bdc35e159bad6da1e08101c8321792d762281"
    ):
        raise RuntimeError("JVM descriptor reference lock does not match the issue pin")
    jar, artifact = reference_jar(args.dependencies.resolve(), lock)
    java = args.java.resolve()
    javap = java.with_name("javap")
    if not java.is_file() or not javap.is_file():
        raise RuntimeError("the supplied Java 21 installation must include java and javap")
    stdlib = args.stdlib_library.resolve()
    if not (stdlib / "manifest.json").is_file():
        raise RuntimeError("a freshly generated KSwiftK stdlib .kklib is required")
    expected = args.expected.read_bytes()

    reference = inspect_jvm_descriptor(javap, jar)
    positive = [
        str(args.compiler.resolve()), "--stdlib-library", str(stdlib), "--no-incremental",
        "--entry-point", "kuu2604.main", str(FIXTURE / "BufferHintEmitProducer.kt"),
        str(FIXTURE / "BufferHintEmitConsumer.kt"), "-o", str(args.output.resolve() / "positive"),
    ]
    args.output.mkdir(parents=True, exist_ok=False)
    candidate_root = args.compiler.resolve().parents[2]
    candidate_environment = {
        **os.environ,
        "TMPDIR": str(args.output.resolve()) + "/",
        "KSWIFTK_PACKAGE_ROOT": str(candidate_root),
    }
    candidate_compile = run(positive, env=candidate_environment)
    candidate_run = (run([str(args.output.resolve() / "positive")], env=candidate_environment)
                     if candidate_compile["exit_code"] == 0 else None)

    negative = [
        str(args.compiler.resolve()), "--stdlib-library", str(stdlib), "--no-incremental",
        "--entry-point", "kuu2604.main", str(FIXTURE / "BufferHintEmitNegativeOptIn.kt"),
        "-o", str(args.output.resolve() / "negative"),
    ]
    negative_result = run(negative, env=candidate_environment)
    diagnostic = negative_result["stdout"] + negative_result["stderr"]
    positive_passed = (
        candidate_compile["exit_code"] == 0
        and not candidate_compile["stderr"]
        and candidate_run is not None
        and candidate_run["exit_code"] == 0
        and not candidate_run["stderr"]
        and candidate_run["stdout"] == expected
    )
    negative_passed = (
        negative_result["exit_code"] != 0
        and b"KSWIFTK-SEMA-OPT-IN" in diagnostic
        and b"kotlinx.io.InternalIoApi" in diagnostic
    )
    failure_reasons = []
    if not positive_passed:
        failure_reasons.append("candidate opted-in KLIB consumer did not match the pinned JVM output")
    if not negative_passed:
        failure_reasons.append("negative consumer did not report the exact InternalIoApi opt-in error")

    candidate_output = json.dumps({
        "positive_compile_stdout_sha256": candidate_compile["stdout_sha256"],
        "positive_compile_stderr_sha256": candidate_compile["stderr_sha256"],
        "positive_run_exit_code": candidate_run["exit_code"] if candidate_run else None,
        "positive_run_stdout_sha256": candidate_run["stdout_sha256"] if candidate_run else None,
        "positive_run_stderr_sha256": candidate_run["stderr_sha256"] if candidate_run else None,
        "negative_compile_stdout_sha256": negative_result["stdout_sha256"],
        "negative_compile_stderr_sha256": negative_result["stderr_sha256"],
        "negative_exit_code": negative_result["exit_code"],
    }, sort_keys=True, separators=(",", ":")).encode()
    candidate_commands = [candidate_compile["command"]]
    if candidate_run is not None:
        candidate_commands.append(candidate_run["command"])
    candidate_commands.append(negative)
    candidate_exit_code = 0
    if candidate_compile["exit_code"] != 0:
        candidate_exit_code = candidate_compile["exit_code"]
    elif candidate_run is not None and candidate_run["exit_code"] != 0:
        candidate_exit_code = candidate_run["exit_code"]
    elif failure_reasons:
        candidate_exit_code = 1
    candidate = {
        "result": "PASS" if not failure_reasons else "FAIL",
        "failure_reasons": failure_reasons,
        "command_sha256": command_digest([item for command in candidate_commands for item in command]),
        "exit_code": candidate_exit_code,
        "stdout_sha256": digest(candidate_run["stdout"] if candidate_run else b""),
        "stderr_sha256": digest(candidate_compile["stderr"] + (candidate_run["stderr"] if candidate_run else b"")),
        "receipt_sha256": digest(candidate_output),
        "candidate_sha": candidate_sha,
    }
    expected_hash = digest(expected)
    descriptor_text = json.dumps({
        "reference_version": lock["kotlinx_io"],
        "reference_commit": lock["commit"],
        "jvm_artifact": artifact["coordinate"],
        "jvm_artifact_sha256": file_digest(jar),
        "candidate_sha": candidate_sha,
        "stdlib_files": sorted((path.relative_to(stdlib).as_posix(), file_digest(path))
                               for path in stdlib.rglob("*") if path.is_file()),
        "expected_stdout_sha256": expected_hash,
        "reference": {
            "result": "PASS", "exit_code": reference["exit_code"],
            "command_sha256": reference["command_sha256"], "stdout_sha256": reference["stdout_sha256"],
            "stderr_sha256": reference["stderr_sha256"], "descriptor": reference["descriptor"],
            "visibility": reference["visibility"], "internal_io_api": reference["internal_io_api"],
            "default_bridge": reference["default_bridge"],
        },
        "candidate": candidate,
        "positive_compile": {
            "exit_code": candidate_compile["exit_code"],
            "command_sha256": candidate_compile["command_sha256"],
            "stdout_sha256": candidate_compile["stdout_sha256"],
            "stderr_sha256": candidate_compile["stderr_sha256"],
        },
        "positive_run": None if candidate_run is None else {
            "exit_code": candidate_run["exit_code"],
            "command_sha256": candidate_run["command_sha256"],
            "stdout_sha256": candidate_run["stdout_sha256"],
            "stderr_sha256": candidate_run["stderr_sha256"],
        },
        "negative_opt_in": {
            "result": "PASS" if negative_passed else "FAIL",
            "exit_code": negative_result["exit_code"],
            "command_sha256": negative_result["command_sha256"],
            "diagnostic_sha256": digest(diagnostic),
            "diagnostic_bytes": len(diagnostic),
        },
    }, ensure_ascii=False, indent=2) + "\n"
    output = args.output.resolve()
    (output / "reference.javap.txt").write_bytes(reference["stdout"])
    (output / "candidate.compile.stdout").write_bytes(candidate_compile["stdout"])
    (output / "candidate.compile.stderr").write_bytes(candidate_compile["stderr"])
    (output / "candidate.stdout").write_bytes(candidate_run["stdout"] if candidate_run else b"")
    (output / "candidate.stderr").write_bytes(candidate_compile["stderr"] + (candidate_run["stderr"] if candidate_run else b""))
    (output / "negative.diagnostics").write_bytes(diagnostic)
    (output / "negative.stdout").write_bytes(negative_result["stdout"])
    (output / "negative.stderr").write_bytes(negative_result["stderr"])
    (output / "receipt.json").write_text(descriptor_text, encoding="utf-8")
    print(json.dumps({"status": "PASS" if not failure_reasons else "FAIL",
                      "receipt": str(output / "receipt.json"),
                      "candidate_sha": candidate_sha, "jvm_descriptor": "()V",
                      "candidate_result": candidate["result"],
                      "expected_stdout_sha256": expected_hash}, ensure_ascii=False))
    return 0 if not failure_reasons else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
