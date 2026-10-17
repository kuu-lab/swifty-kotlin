#!/usr/bin/env python3
"""Run the focused JVM ABI, upstream assertion and Native KLIB gates for KUU-2639."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

import generate


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
CASE_ID = generate.KUU_2639_CASE_ID
ROW_ID = generate.KUU_2639_ROW_ID
NATIVE_SOURCE_CLOSURE = HERE / "unsafe-buffer-move-to-tail-defaults.source-closure.json"
NATIVE_TEST_SUPPORT = ROOT / generate.KUU_2639_NATIVE_TEST_SUPPORT
LANES = [
    ("source-O0", "source", "O0", False),
    ("source-O2", "source", "O2", False),
    ("stdlib-library-O0", "stdlib-library", "O0", False),
    ("stdlib-library-O2", "stdlib-library", "O2", False),
    ("producer-consumer-O0", "producer-consumer", "O0", True),
    ("producer-consumer-O2", "producer-consumer", "O2", True),
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run_stage(command: list[str], output: Path, name: str, timeout: float,
              environment: dict[str, str] | None = None) -> int:
    command_path = output / f"{name}.command.json"
    stdout_path = output / f"{name}.stdout"
    stderr_path = output / f"{name}.stderr"
    result_path = output / f"{name}.result.json"
    save(command_path, command)
    started = time.monotonic()
    timed_out = False
    with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
        child = subprocess.Popen(command, cwd=ROOT, env={**os.environ, **(environment or {})},
                                 stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            code = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            code = 124
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                child.wait()
    save(result_path, {"exit_code": code, "timeout": timed_out,
                       "seconds": round(time.monotonic() - started, 3),
                       "stdout_sha256": sha256(stdout_path), "stderr_sha256": sha256(stderr_path)})
    if code != 0:
        raise RuntimeError(f"stage failed: {name}; see {stdout_path} and {stderr_path}")
    return code


def require_pass(summary_path: Path, expected_id: str | None = None) -> dict:
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    if summary.get("status") != "PASS":
        raise RuntimeError(f"candidate runner did not pass: {summary_path}")
    if expected_id is not None:
        results = json.loads((summary_path.parent / "results.json").read_text(encoding="utf-8"))
        if len(results) != 1 or results[0].get("execution_id") != expected_id or results[0].get("status") != "PASS":
            raise RuntimeError(f"candidate result did not match the selected case: {summary_path}")
    return summary


def load_row() -> dict:
    with (HERE / "api-inventory.tsv").open(encoding="utf-8", newline="") as stream:
        rows = [row for row in csv.DictReader(stream, delimiter="\t") if row.get("row_id") == ROW_ID]
    if len(rows) != 1:
        raise RuntimeError(f"expected exactly one generated inventory row for {ROW_ID}")
    return rows[0]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--kotlin-home", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True)
    parser.add_argument("--dependencies", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--compile-timeout", type=float, default=600)
    parser.add_argument("--run-timeout", type=float, default=60)
    args = parser.parse_args(argv)

    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    compiler = args.compiler.resolve()
    if not compiler.is_file():
        raise SystemExit(f"compiler binary is missing: {compiler}; run swift build first")
    candidate_sha = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    compiler_sha = sha256(compiler)
    native_test_support_sha = sha256(NATIVE_TEST_SUPPORT)
    report: dict = {"schema_version": 1, "row_id": ROW_ID, "case_id": CASE_ID,
                    "candidate_sha": candidate_sha, "status": "RUNNING", "stages": []}
    try:
        # First run the standalone external consumer. This builds a fresh stdlib KLIB and
        # checks its output against the pinned Kotlin/JVM reference in all six lanes.
        matrix_dir = output / "dedicated-consumer-matrix"
        run_stage([
            sys.executable, str(HERE / "run_f02_matrix.py"),
            "--compiler", str(compiler), "--kotlin-home", str(args.kotlin_home.resolve()),
            "--java", str(args.java.resolve()), "--dependencies", str(args.dependencies.resolve()),
            "--case", generate.KUU_2639_CONSUMER_CASE_ID, "--separate-cases",
            "--compile-timeout", str(args.compile_timeout), "--output", str(matrix_dir),
        ], output, "dedicated-consumer-matrix", args.compile_timeout * 7)
        matrix_summary = json.loads((matrix_dir / "summary.json").read_text(encoding="utf-8"))
        matrix_receipt = {
            "summary_sha256": generate.canonical_json_sha256(matrix_summary),
            "summary": matrix_summary,
        }
        stdlib = output / "dedicated-consumer-matrix/KSwiftKStdlib.kklib"
        if not (stdlib / "manifest.json").is_file():
            raise RuntimeError("the dedicated consumer did not produce a fresh stdlib KLIB")
        report["dedicated_consumer_matrix"] = matrix_receipt
        report["fresh_stdlib_klib_sha256"] = generate.canonical_json_sha256(
            {str(path.relative_to(stdlib)): sha256(path) for path in sorted(stdlib.rglob("*")) if path.is_file()}
        )

        # Run the untouched upstream assertion and direct JVM reflection probe against
        # the pinned 0.9.1 artifact. These are separate from Native candidate lanes.
        upstream_dir = output / "upstream-jvm-case"
        run_stage([
            sys.executable, str(ROOT / "Scripts/kotlinx_io_upstream/run_jvm_reference_case.py"),
            "--upstream", str(args.upstream.resolve()), "--kotlin-home", str(args.kotlin_home.resolve()),
            "--java", str(args.java.resolve()), "--dependencies", str(args.dependencies.resolve()),
            "--upstream-id", CASE_ID, "--compile-timeout", str(args.compile_timeout),
            "--run-timeout", str(args.run_timeout), "--output", str(upstream_dir),
        ], output, "upstream-jvm-case", args.compile_timeout + args.run_timeout)
        upstream_case = json.loads((upstream_dir / "report.json").read_text(encoding="utf-8"))
        report["upstream_jvm_case"] = upstream_case

        probe_path = output / "jvm-bridge-probe.json"
        run_stage([
            sys.executable, str(HERE / "probes/run_unsafe_buffer_move_to_tail_default_bridge_probe.py"),
            "--kotlin-home", str(args.kotlin_home.resolve()), "--java", str(args.java.resolve()),
            "--dependencies", str(args.dependencies.resolve()), "--output", str(probe_path),
        ], output, "jvm-bridge-probe", 60)
        probe_report = json.loads(probe_path.read_text(encoding="utf-8"))
        report["jvm_bridge_probe"] = {
            "report_sha256": generate.canonical_json_sha256(probe_report),
            "report": probe_report,
        }

        jvm_execution_id = upstream_case["execution_id"]
        if upstream_case.get("result") != "PASS" or upstream_case.get("passed_count") != 1:
            raise RuntimeError("the exact upstream JVM assertion is not a single PASS")
        native_catalog = json.loads((ROOT / "Scripts/kotlinx_io_upstream/native-executions.expected.json").read_text())
        native_rows = [row for row in native_catalog if row.get("upstream_id") == CASE_ID]
        if len(native_rows) != 1:
            raise RuntimeError("the exact original method is absent or ambiguous in the Native execution catalog")
        native_execution_id = native_rows[0]["execution_id"]

        candidate_receipts = []
        execution_evidence = []
        for lane, route, optimization, test_library in LANES:
            lane_dir = output / f"candidate-{lane}"
            command = [
                sys.executable, str(ROOT / "Scripts/kotlinx_io_upstream/run_candidate_suites.py"),
                "--upstream", str(args.upstream.resolve()), "--compiler", str(compiler),
                "--package-root", str(ROOT), "--native-catalog", "macos",
                "--source-closure-index", str(NATIVE_SOURCE_CLOSURE),
                "--support-source", str(NATIVE_TEST_SUPPORT),
                "--source-function-id", CASE_ID, "--optimization", optimization,
                "--compile-timeout", str(args.compile_timeout), "--run-timeout", str(args.run_timeout),
                "--output", str(lane_dir),
            ]
            if route == "source":
                command.append("--stdlib-from-source")
            else:
                command += ["--stdlib-library", str(stdlib)]
            if test_library:
                command.append("--test-library")
            stage_name = "candidate-" + lane
            run_stage(command, output, stage_name, args.compile_timeout * 2 + args.run_timeout)
            summary_path = lane_dir / "summary.json"
            summary = require_pass(summary_path, native_execution_id)
            expected_support_inputs = {str(NATIVE_TEST_SUPPORT.resolve()): native_test_support_sha}
            if summary.get("inputs", {}).get("support_source_sha256") != expected_support_inputs:
                raise RuntimeError(f"candidate lane {lane} did not compile the pinned test support source")
            results_path = lane_dir / "results.json"
            results = json.loads(results_path.read_text(encoding="utf-8"))
            result_ids = [item.get("execution_id") for item in results]
            if result_ids != [native_execution_id]:
                raise RuntimeError(f"candidate lane {lane} selected a different original execution")
            stage_result = json.loads((output / f"{stage_name}.result.json").read_text())
            inputs_sha = generate.canonical_json_sha256(summary["inputs"])
            candidate_receipts.append({
                "lane": lane,
                "execution_id": native_execution_id,
                "result": "PASS",
                "exit_code": 0,
                "selected_count": 1,
                "passed_count": 1,
                "run_stdout_sha256": sha256(lane_dir / "run.stdout"),
                "run_stderr_sha256": sha256(lane_dir / "run.stderr"),
                "results_sha256": sha256(results_path),
                "summary_sha256": sha256(summary_path),
                "executable_sha256": summary["executable_sha256"],
                "runner_inputs_sha256": inputs_sha,
                "test_support_source_sha256": native_test_support_sha,
            })
            execution_evidence.append({
                "case_id": CASE_ID,
                "lane": lane,
                "reference": {"execution_id": jvm_execution_id, "result": "PASS", "exit_code": 0},
                "candidate": {"execution_id": native_execution_id, "result": "PASS", "exit_code": 0},
            })
            report["stages"].append({"lane": lane, "result": "PASS",
                                     "runner_seconds": stage_result["seconds"],
                                     "receipt": candidate_receipts[-1]})

        if subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip() != candidate_sha:
            raise RuntimeError("candidate HEAD changed during the KUU-2639 evidence run")
        if sha256(compiler) != compiler_sha:
            raise RuntimeError("compiler changed during the KUU-2639 evidence run")

        row = load_row()
        input_hashes = generate.validation_input_hashes(row)
        evidence_record = {
            "row_id": ROW_ID,
            "candidate_sha": candidate_sha,
            "reference_version": "0.9.1",
            "reference_commit": "362bdc35e159bad6da1e08101c8321792d762281",
            "evidence_source": "upstream-catalog",
            **input_hashes,
            "compatibility_obligations": ["native-source", "native-bridge"],
            "executions": execution_evidence,
            "specialized_evidence": {
                "policy": generate.KUU_2639_SPECIAL_EVIDENCE_POLICY,
                "native_source_closure_sha256": sha256(NATIVE_SOURCE_CLOSURE),
                "native_test_support_sha256": native_test_support_sha,
                "upstream_jvm_case": upstream_case,
                "jvm_bridge_probe": report["jvm_bridge_probe"],
                "candidate_lane_receipts": candidate_receipts,
                "dedicated_consumer_matrix": matrix_receipt,
            },
        }
        report["evidence_record"] = evidence_record
        evidence_path = HERE / "api-validation-evidence.json"
        original_evidence = evidence_path.read_bytes()
        evidence = json.loads(original_evidence.decode("utf-8"))
        if evidence.get("schema_version") != generate.VALIDATION_EVIDENCE_SCHEMA_VERSION:
            raise RuntimeError("unsupported API evidence schema")
        records = [record for record in evidence["records"] if record.get("row_id") != ROW_ID]
        records.append(evidence_record)
        evidence["records"] = sorted(records, key=lambda record: record["row_id"])
        evidence_path.write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        try:
            subprocess.run([sys.executable, str(HERE / "generate.py"), "--write"], cwd=ROOT, check=True)
            subprocess.run([sys.executable, str(HERE / "generate.py"), "--check"], cwd=ROOT, check=True)
        except subprocess.CalledProcessError:
            evidence_path.write_bytes(original_evidence)
            raise
        report["status"] = "PASS"
        report["evidence_file"] = str(evidence_path)
        report["inventory_regeneration"] = "PASS; KUU-2639 JVM ABI row remains unverified by policy"
    except Exception as error:
        report.update({"status": "FAILED_OR_INCOMPLETE", "error": str(error)})
        save(output / "report.json", report)
        print(str(error), file=sys.stderr)
        return 1

    save(output / "report.json", report)
    print(json.dumps({"status": report["status"], "row_id": ROW_ID,
                      "candidate_sha": candidate_sha, "output": str(output),
                      "evidence_file": report["evidence_file"]}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
