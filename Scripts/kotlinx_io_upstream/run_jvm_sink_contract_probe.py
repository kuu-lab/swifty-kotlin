#!/usr/bin/env python3
"""Run API-contract probes against the locked kotlinx-io JVM artifact."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import time

HERE = Path(__file__).resolve().parent
LOCK_PATH = HERE / "reference-lock.json"
PROBE_SOURCE = HERE / "fixtures/jvm_sink_contract_probe.kt"
EXPECTED_PATH = HERE / "jvm-sink-contract-probe.expected.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], output: Path, name: str, timeout: float) -> dict:
    started = time.monotonic()
    completed = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    (output / f"{name}.command.json").write_text(json.dumps(command, indent=2) + "\n")
    (output / f"{name}.stdout").write_text(completed.stdout)
    (output / f"{name}.stderr").write_text(completed.stderr)
    result = {
        "exitcode": completed.returncode,
        "seconds": round(time.monotonic() - started, 3),
        "stdout_sha256": hashlib.sha256(completed.stdout.encode()).hexdigest(),
        "stderr_sha256": hashlib.sha256(completed.stderr.encode()).hexdigest(),
    }
    (output / f"{name}.result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kotlin-home", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    summary = {
        "kind": "locked-jvm-sink-contract-probe",
        "status": "NOT_RUN",
        "host": platform.platform(),
        "checks": 4,
    }
    try:
        lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
        if sha256(PROBE_SOURCE) != lock["jvm_sink_contract_probe_source_sha256"]:
            raise ValueError("JVM Sink contract probe source differs from reference lock")
        if sha256(EXPECTED_PATH) != lock["jvm_sink_contract_probe_expected_sha256"]:
            raise ValueError("JVM Sink contract probe expectations differ from reference lock")
        artifacts = {row["coordinate"].split(":")[1]: row for row in lock["jvm_artifacts"]}
        core_record = artifacts["kotlinx-io-core-jvm"]
        bytestring_record = artifacts["kotlinx-io-bytestring-jvm"]
        core_jar = args.dependencies / core_record["url"].rsplit("/", 1)[1]
        bytestring_jar = args.dependencies / bytestring_record["url"].rsplit("/", 1)[1]
        for path, record in ((core_jar, core_record), (bytestring_jar, bytestring_record)):
            if sha256(path) != record["sha256"]:
                raise ValueError(f"locked JVM artifact is missing or has a different SHA-256: {path}")
        compiler = args.kotlin_home / "bin/kotlinc"
        if not compiler.is_file() or not args.java.is_file():
            raise ValueError("locked Kotlin compiler or Java executable is missing")
        expected = json.loads(EXPECTED_PATH.read_text(encoding="utf-8"))
        main_source = args.output / "JvmSinkContractProbeMain.kt"
        main_source.write_text(
            "import kotlinx.io.contractprobe.verifySinkWriteStringContracts\n\n"
            "fun main() { println(verifySinkWriteStringContracts()) }\n",
            encoding="utf-8",
        )
        probe_copy = args.output / PROBE_SOURCE.name
        probe_copy.write_bytes(PROBE_SOURCE.read_bytes())
        classpath = f"{core_jar.resolve()}:{bytestring_jar.resolve()}"
        jar = args.output / "probe.jar"
        compile_result = run(
            [str(compiler.resolve()), "-classpath", classpath, str(probe_copy), str(main_source),
             "-include-runtime", "-d", str(jar)],
            args.output, "compile", args.timeout,
        )
        summary.update({
            "reference_version": lock["kotlinx_io"],
            "reference_commit": lock["commit"],
            "artifacts": {"core": core_record["sha256"], "bytestring": bytestring_record["sha256"]},
            "probe_source_sha256": sha256(PROBE_SOURCE),
            "expected_contract_sha256": sha256(EXPECTED_PATH),
            "compile_result": compile_result,
        })
        if compile_result["exitcode"] != 0:
            raise ValueError("reference contract probe failed to compile")
        run_result = run(
            [str(args.java.resolve()), "-cp", f"{jar.resolve()}:{classpath}", "JvmSinkContractProbeMainKt"],
            args.output, "run", args.timeout,
        )
        actual = (args.output / "run.stdout").read_text(encoding="utf-8").strip()
        status = "PASS" if run_result["exitcode"] == 0 and actual == expected["expected_output"] else "FAIL"
        result = {
            "status": status,
            "expected": expected["expected_output"],
            "actual": actual,
            "checks": expected["checks"],
            "probe_source_sha256": sha256(PROBE_SOURCE),
            "expected_contract_sha256": sha256(EXPECTED_PATH),
            "reference_artifacts": summary["artifacts"],
        }
        result_path = args.output / "contract-probe-results.json"
        result_path.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        summary.update({
            "run_result": run_result,
            "actual": actual,
            "contract_probe_result": result_path.name,
            "contract_probe_result_sha256": sha256(result_path),
            "status": status,
        })
        return 0 if status == "PASS" else 1
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        summary.update({"status": "ERROR", "error": str(error)})
        (args.output / "error.txt").write_text(str(error) + "\n", encoding="utf-8")
        return 1
    finally:
        (args.output / "summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
                                                  encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
