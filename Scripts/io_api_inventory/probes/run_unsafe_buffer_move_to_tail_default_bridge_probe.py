#!/usr/bin/env python3
"""Run and receipt the pinned JVM default-bridge reflection probe."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
ROW_ID = "jvm-8178a8b4ccb3fdd8"
PROBE_ID = "JVMABIReflectionLedgerProbe#" + ROW_ID
REFERENCE_VERSION = "0.9.1"
REFERENCE_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"
ARTIFACT_COORDINATE = "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1"
JAVA_SOURCE = HERE / "UnsafeBufferOperationsMoveToTailDefaultBridgeProbe.java"
EXPECTED_PATH = HERE / "unsafe_buffer_move_to_tail_default_bridge.expected.json"
REPOSITORY_PROBE_PATH = JAVA_SOURCE.relative_to(ROOT).as_posix()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kotlin-home", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)

    lock = json.loads((ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json").read_text())
    if (lock.get("kotlinx_io"), lock.get("commit")) != (REFERENCE_VERSION, REFERENCE_COMMIT):
        raise SystemExit("reference lock differs from the probe contract")
    java_version = subprocess.run([str(args.java.resolve()), "-version"], text=True,
                                  capture_output=True, check=False)
    version_text = java_version.stdout + java_version.stderr
    version_match = re.search(r'version "(\d+)(?:\.[^"]*)?"', version_text)
    if java_version.returncode != 0 or version_match is None or version_match.group(1) != "21":
        raise SystemExit("the pinned JVM bridge probe requires a Java 21 runtime")
    artifact = next((row for row in lock["jvm_artifacts"] if row["coordinate"] == ARTIFACT_COORDINATE), None)
    if artifact is None:
        raise SystemExit("pinned kotlinx-io core JVM artifact is missing from reference-lock.json")
    jar = args.dependencies / artifact["url"].rsplit("/", 1)[-1]
    if sha256(jar) != artifact["sha256"]:
        raise SystemExit("pinned kotlinx-io core JVM artifact SHA-256 mismatch")
    stdlib = args.kotlin_home / "lib/kotlin-stdlib.jar"
    sdk_record = next((row for row in lock["sdk_files"] if row["path"] == "lib/kotlin-stdlib.jar"), None)
    if sdk_record is None or sha256(stdlib) != sdk_record["sha256"]:
        raise SystemExit("pinned Kotlin 2.3.10 stdlib SHA-256 mismatch")

    javac = args.java.resolve().with_name("javac")
    if not javac.is_file():
        raise SystemExit(f"JDK compiler not found beside Java runtime: {javac}")
    with tempfile.TemporaryDirectory(prefix="kuu2639-jvm-probe-") as temporary:
        classes = Path(temporary) / "classes"
        classes.mkdir()
        compile_result = subprocess.run(
            [str(javac), "--release", "21", "-d", str(classes), str(JAVA_SOURCE)],
            text=True, capture_output=True, check=False,
        )
        if compile_result.returncode != 0 or compile_result.stderr:
            raise SystemExit("javac failed: " + compile_result.stderr.strip())
        runtime_classpath = ":".join(map(str, (classes, jar.resolve(), stdlib.resolve())))
        run_result = subprocess.run(
            [str(args.java.resolve()), "-cp", runtime_classpath,
             "UnsafeBufferOperationsMoveToTailDefaultBridgeProbe"],
            text=True, capture_output=True, check=False,
        )
        if run_result.returncode != 0 or run_result.stderr:
            raise SystemExit("JVM reflection probe failed: " + run_result.stderr.strip())
        try:
            observed = json.loads(run_result.stdout)
        except json.JSONDecodeError as error:
            raise SystemExit(f"JVM reflection probe returned invalid JSON: {error}") from error

    expected = json.loads(EXPECTED_PATH.read_text(encoding="utf-8"))
    if any(observed.get(key) != value for key, value in expected.items()):
        raise SystemExit("JVM reflection output does not match the pinned bridge contract")
    assertion_count = observed.get("assertion_count")
    if type(assertion_count) is not int or assertion_count < 20:
        raise SystemExit("JVM reflection probe did not run the required assertions")

    report = {
        "schema_version": 1,
        "probe_id": PROBE_ID,
        "row_id": ROW_ID,
        "candidate_sha": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip(),
        "reference_version": REFERENCE_VERSION,
        "reference_commit": REFERENCE_COMMIT,
        "artifact_coordinate": ARTIFACT_COORDINATE,
        "artifact_sha256": artifact["sha256"],
        "probe_source_path": REPOSITORY_PROBE_PATH,
        "probe_source_sha256": sha256(JAVA_SOURCE),
        "expected_contract_path": EXPECTED_PATH.relative_to(ROOT).as_posix(),
        "expected_contract_sha256": sha256(EXPECTED_PATH),
        "probe_stdout_sha256": hashlib.sha256(run_result.stdout.encode()).hexdigest(),
        "probe_stderr_sha256": hashlib.sha256(run_result.stderr.encode()).hexdigest(),
        "java_runtime_major": 21,
        "java_version_sha256": hashlib.sha256(version_text.encode()).hexdigest(),
        "probe": observed,
        "result": "PASS",
        "exit_code": 0,
    }
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"probe_id": PROBE_ID, "row_id": ROW_ID, "candidate_sha": report["candidate_sha"],
                      "assertion_count": assertion_count, "report": str(output),
                      "report_sha256": sha256(output), "result": "PASS"}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
