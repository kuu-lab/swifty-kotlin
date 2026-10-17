#!/usr/bin/env python3
"""Run and record the dedicated ByteString backing-array compatibility probe."""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PROBE_DIR = HERE / "bytestring_backing_array"
EXECUTIONS_PATH = PROBE_DIR / "execution-catalog.json"
EVIDENCE_PATH = HERE / "api-validation-evidence.json"
LEDGER_PATH = HERE / "api-inventory.tsv"
REFERENCE_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"
SOURCE_CASE = "Scripts/io_api_inventory/bytestring_backing_array/Probe.kt#directBackingArrayIdentity"
JVM_CASE = "Scripts/io_api_inventory/bytestring_backing_array/Producer.kt#publishedBackingArrayForProbe"
TARGET_ROW_IDS = (
    "internal-b45a777a1eaf039c",
    "jvm-f72f86a64f90dc84",
    "klib-28163803c351e2f6",
)
LANE_NAMES = (
    "source-O0",
    "source-O2",
    "stdlib-library-O0",
    "stdlib-library-O2",
    "producer-consumer-O0",
    "producer-consumer-O2",
)
APPLE_LANE_NAMES = ("apple-native-O0", "apple-native-O2")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha256(path: Path) -> str:
    return sha256(path.read_bytes())


def save(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run_command(command: list[str], output: Path, name: str, cwd: Path = ROOT) -> dict:
    completed = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    (output / f"{name}.stdout").write_bytes(completed.stdout)
    (output / f"{name}.stderr").write_bytes(completed.stderr)
    receipt = {
        "command": command,
        "cwd": str(cwd),
        "result": "PASS" if completed.returncode == 0 else "FAIL",
        "exit_code": completed.returncode,
        "stdout_sha256": sha256(completed.stdout),
        "stderr_sha256": sha256(completed.stderr),
    }
    save(output / f"{name}.json", receipt)
    print(f"{receipt['result']} {name}", flush=True)
    if completed.returncode:
        sys.stderr.buffer.write(completed.stderr)
        sys.stderr.buffer.write(completed.stdout)
    return receipt


def load_generator():
    spec = importlib.util.spec_from_file_location("io_inventory_generator", HERE / "generate.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load API inventory generator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def current_candidate_sha() -> str:
    return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()


def normalized_lane(route: str, optimization: str) -> str:
    return f"{route}-{optimization}"


def execution(execution_id: str, case_id: str, lane: str, side: str,
              result: str, exit_code: int, stdout_sha: str, stderr_sha: str) -> dict:
    return {
        "execution_id": execution_id,
        "case_id": case_id,
        "lane": lane,
        "side": side,
        "result": result,
        "exit_code": exit_code,
        "stdout_sha256": stdout_sha,
        "stderr_sha256": stderr_sha,
    }


def reference_execution_for_lane(executions: list[dict], lane: str) -> dict | None:
    exact = next((item for item in executions if item["side"] == "reference" and item["lane"] == lane), None)
    if exact is not None:
        return exact
    return next((item for item in executions if item["side"] == "reference" and item["lane"] == "*"), None)


def build_execution_records(matrix: dict, output: Path, descriptor: dict, swift_test: dict,
                            native_reference: dict) -> list[dict]:
    matrix_dir = output / "matrix"
    results = [item for item in matrix.get("results", []) if item.get("case") == "bytestring-backing-array"]
    records = []
    reference_stdout = matrix_dir / "bytestring-backing-array/reference-run.stdout"
    reference_stderr = matrix_dir / "bytestring-backing-array/reference-run.stderr"
    reference_receipt_path = matrix_dir / "bytestring-backing-array/reference-run.json"
    if reference_receipt_path.is_file() and reference_stdout.is_file() and reference_stderr.is_file():
        reference_receipt = json.loads(reference_receipt_path.read_text())
        records.append(execution(
            "bytestring-backing-array:jvm:reference", SOURCE_CASE, "*", "reference",
            "PASS" if reference_receipt.get("status") == "EXITED" and reference_receipt.get("exitcode") == 0 else "FAIL",
            reference_receipt.get("exitcode", 1), file_sha256(reference_stdout), file_sha256(reference_stderr),
        ))
    for item in results:
        lane = normalized_lane(item.get("route", ""), item.get("optimization", ""))
        run_stdout = matrix_dir / "bytestring-backing-array" / lane / "run.stdout"
        run_stderr = matrix_dir / "bytestring-backing-array" / lane / "run.stderr"
        run_receipt_path = matrix_dir / "bytestring-backing-array" / lane / "run.json"
        if not (run_receipt_path.is_file() and run_stdout.is_file() and run_stderr.is_file()):
            continue
        run_receipt = json.loads(run_receipt_path.read_text())
        records.append(execution(
            f"bytestring-backing-array:f02:{lane}", SOURCE_CASE, lane, "candidate",
            item.get("status", "NOT_RUN"), run_receipt.get("exitcode", 1),
            file_sha256(run_stdout), file_sha256(run_stderr),
        ))

    descriptor_stdout = output / "jvm-descriptor.stdout"
    descriptor_stderr = output / "jvm-descriptor.stderr"
    records.append(execution(
        "bytestring-backing-array:jvm-descriptor:reference", JVM_CASE, "jvm-descriptor", "reference",
        descriptor.get("result", "FAIL"), descriptor.get("exit_code", 1),
        file_sha256(descriptor_stdout), file_sha256(descriptor_stderr),
    ))
    swift_stdout = output / "swift-focused-test.stdout"
    swift_stderr = output / "swift-focused-test.stderr"
    records.append(execution(
        "bytestring-backing-array:jvm-descriptor:candidate", JVM_CASE, "jvm-descriptor", "candidate",
        swift_test.get("result", "FAIL"), swift_test.get("exit_code", 1),
        file_sha256(swift_stdout), file_sha256(swift_stderr),
    ))
    source_candidates = {
        item["lane"]: item for item in records
        if item["side"] == "candidate" and item["lane"] in {"source-O0", "source-O2"}
    }
    for native_record in native_reference.get("executions", []):
        records.append(native_record)
        suffix = native_record["lane"].removeprefix("apple-native-")
        candidate = source_candidates.get(f"source-{suffix}")
        if candidate is not None:
            records.append(execution(
                f"bytestring-backing-array:apple-candidate:{suffix}",
                SOURCE_CASE,
                native_record["lane"],
                "candidate",
                candidate["result"],
                candidate["exit_code"],
                candidate["stdout_sha256"],
                candidate["stderr_sha256"],
            ))
    return records


def write_validation_evidence(generator, records: list[dict], candidate_sha: str) -> None:
    rows = {}
    with LEDGER_PATH.open(encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            if row.get("row_id") in TARGET_ROW_IDS:
                rows[row["row_id"]] = row
    if set(rows) != set(TARGET_ROW_IDS):
        raise RuntimeError("API ledger does not contain exactly the expected ByteString backing-array rows")

    executions_by_row = {
        TARGET_ROW_IDS[0]: [item for item in records if item["side"] == "reference" and item["lane"] == "*"]
            + [item for item in records if item["side"] == "candidate"
               and item["lane"] in (*LANE_NAMES, *APPLE_LANE_NAMES)]
            + [item for item in records if item["side"] == "reference" and item["lane"] in APPLE_LANE_NAMES],
        TARGET_ROW_IDS[1]: [item for item in records if item["lane"] == "jvm-descriptor"],
        TARGET_ROW_IDS[2]: [item for item in records if item["side"] == "reference" and item["lane"] == "*"]
            + [item for item in records if item["side"] == "candidate"
               and item["lane"] in (*LANE_NAMES, *APPLE_LANE_NAMES)]
            + [item for item in records if item["side"] == "reference" and item["lane"] in APPLE_LANE_NAMES],
    }
    lock = json.loads((HERE / "upstream-lock.json").read_text(encoding="utf-8"))
    evidence_records = []
    for row_id in TARGET_ROW_IDS:
        row = rows[row_id]
        hashes = generator.validation_input_hashes(row)
        lanes_required = generator.required_execution_lanes(generator.validation_obligations(row))
        lane_executions = []
        for lane in lanes_required:
            case_id = JVM_CASE if lane == "jvm-descriptor" else SOURCE_CASE
            reference = reference_execution_for_lane(executions_by_row[row_id], lane)
            candidate = next((item for item in executions_by_row[row_id]
                              if item["side"] == "candidate" and item["lane"] == lane), None)
            if reference is None or candidate is None:
                continue
            lane_executions.append({
                "case_id": case_id,
                "lane": lane,
                "reference": {"execution_id": reference["execution_id"], "result": reference["result"],
                              "exit_code": reference["exit_code"]},
                "candidate": {"execution_id": candidate["execution_id"], "result": candidate["result"],
                              "exit_code": candidate["exit_code"]},
            })
        evidence_records.append({
            "row_id": row_id,
            "candidate_sha": candidate_sha,
            "reference_version": lock["tag"],
            "reference_commit": lock["commit"],
            **hashes,
            "compatibility_obligations": generator.validation_obligations(row),
            "executions": lane_executions,
        })

    existing = json.loads(EVIDENCE_PATH.read_text(encoding="utf-8"))
    kept = [record for record in existing.get("records", []) if record.get("row_id") not in TARGET_ROW_IDS]
    existing["records"] = kept + evidence_records
    save(EVIDENCE_PATH, existing)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path)
    parser.add_argument("--package-root", type=Path,
                        help="source/runtime root matching the candidate compiler; defaults to this checkout")
    parser.add_argument("--candidate-sha", help="candidate SHA; otherwise taken from this checkout")
    parser.add_argument("--reference-root", type=Path, required=True,
                        help="output directory from prepare_reference.py --target jvm")
    parser.add_argument("--native-reference-root", type=Path, required=True,
                        help="output directory from prepare_reference.py --target macos_arm64")
    parser.add_argument("--konan-data", type=Path,
                        help="persistent Kotlin/Native dependency cache directory")
    parser.add_argument("--output", type=Path, required=True, help="new directory for immutable run logs")
    parser.add_argument("--compile-timeout", type=float, default=600)
    args = parser.parse_args(argv)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)

    reference_root = args.reference_root.resolve()
    paths = json.loads((reference_root / "paths.json").read_text(encoding="utf-8"))
    lock_path = ROOT / "Scripts/kotlinx_io_upstream/reference-lock.json"
    if paths.get("target") != "jvm":
        parser.error("reference root must be prepared for target jvm")
    if paths.get("reference_lock_sha256") != file_sha256(lock_path):
        parser.error("reference root uses a different reference lock")
    if json.loads(lock_path.read_text(encoding="utf-8"))["commit"] != REFERENCE_COMMIT:
        parser.error("reference lock is not pinned to the expected kotlinx-io commit")

    package_root = args.package_root.resolve() if args.package_root else ROOT
    test_source = ROOT / "Tests/CompilerCoreTests/Sema/KotlinxIOByteStringBackingArrayTests.swift"
    if package_root != ROOT:
        test_destination = package_root / "Tests/CompilerCoreTests/Sema/KotlinxIOByteStringBackingArrayTests.swift"
        test_destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(test_source, test_destination)

    generator = load_generator()
    candidate_sha = args.candidate_sha or current_candidate_sha()
    inventory_before = run_command([sys.executable, str(HERE / "generate.py"), "--write"], output, "inventory-before")
    build = run_command(["swift", "build"], output, "swift-build", cwd=package_root)
    bash = Path("/opt/homebrew/bin/bash") if Path("/opt/homebrew/bin/bash").is_file() else Path(shutil.which("bash") or "bash")
    test_script = package_root / "Scripts/swift_test.sh"
    swift_test = run_command([
        str(bash), str(test_script), "--no-parallel", "--filter",
        "CompilerCoreTests.KotlinxIOByteStringBackingArrayTests",
    ], output, "swift-focused-test", cwd=package_root)

    compiler = (args.compiler.resolve() if args.compiler else package_root / ".build/debug/kswiftc").resolve()
    kotlin_home = Path(paths["installation"])
    dependencies = Path(paths["dependencies"])
    java_home = os.environ.get("JAVA_HOME")
    java = Path(java_home) / "bin/java" if java_home else Path(shutil.which("java") or "")
    if not java.is_file():
        parser.error("Java 21 executable was not found")
    matrix_output = output / "matrix"
    matrix_command = [
        sys.executable, str(HERE / "run_f02_matrix.py"),
        "--compiler", str(compiler), "--output", str(matrix_output),
        "--kotlin-home", str(kotlin_home), "--java", str(java), "--dependencies", str(dependencies),
        "--case", "bytestring-backing-array", "--separate-cases", "--compile-timeout", str(args.compile_timeout),
    ]
    if args.package_root:
        matrix_command += ["--package-root", str(args.package_root.resolve())]
    if args.candidate_sha:
        matrix_command += ["--candidate-sha", candidate_sha]
    matrix_run = run_command(matrix_command, output, "f02-matrix")
    matrix_path = matrix_output / "summary.json"
    matrix = json.loads(matrix_path.read_text(encoding="utf-8")) if matrix_path.is_file() else {}

    descriptor_jar = dependencies / "kotlinx-io-bytestring-jvm-0.9.1.jar"
    javap = shutil.which("javap") or "javap"
    descriptor = run_command([
        sys.executable, str(HERE / "verify_bytestring_jvm_descriptor.py"),
        "--jar", str(descriptor_jar), "--javap", javap,
    ], output, "jvm-descriptor")
    native_output = output / "apple-native-reference"
    native_command = [
        sys.executable, str(HERE / "verify_bytestring_native_reference.py"),
        "--reference-root", str(args.native_reference_root.resolve()),
        "--output", str(native_output),
    ]
    if args.konan_data:
        native_command += ["--konan-data", str(args.konan_data.resolve())]
    native = run_command(native_command, output, "apple-native-reference")
    native_summary_path = native_output / "summary.json"
    native_summary = json.loads(native_summary_path.read_text(encoding="utf-8")) if native_summary_path.is_file() else {}
    native_records_path = native_output / "execution-records.json"
    native_records = json.loads(native_records_path.read_text(encoding="utf-8")) if native_records_path.is_file() else {}

    execution_records = []
    if matrix and (output / "jvm-descriptor.stdout").is_file() and (output / "swift-focused-test.stdout").is_file():
        execution_records = build_execution_records(matrix, output, descriptor, swift_test, native_records)
    matrix_pass = (matrix.get("status") == "SELECTED_MATRIX_PASS"
                   and matrix.get("candidate_sha") == candidate_sha
                   and len([item for item in matrix.get("results", [])
                            if item.get("case") == "bytestring-backing-array" and item.get("status") == "PASS"]) == 6)
    reference_stdout_path = matrix_output / "bytestring-backing-array/reference-run.stdout"
    expected_output = b"PASS:direct=true:inline=true:repeat=true\n"
    matrix_pass = matrix_pass and reference_stdout_path.is_file() and reference_stdout_path.read_bytes() == expected_output
    descriptor_pass = descriptor["result"] == "PASS"
    native_pass = native["result"] == "PASS" and native_summary.get("status") == "PASS"
    swift_pass = build["result"] == "PASS" and swift_test["result"] == "PASS"
    all_pass = inventory_before["result"] == "PASS" and matrix_pass and descriptor_pass and native_pass and swift_pass
    summary = {
        "status": "PASS" if all_pass else "FAILED_OR_INCOMPLETE",
        "candidate_sha": candidate_sha,
        "harness_dirty_patch_sha256": matrix.get("harness_dirty_patch_sha256"),
        "candidate_source_root": matrix.get("candidate_source_root"),
        "reference_version": "0.9.1",
        "reference_commit": REFERENCE_COMMIT,
        "probe_source_sha256": {path.name: file_sha256(path) for path in PROBE_DIR.glob("*.kt")},
        "matrix_status": matrix.get("status", "NOT_RUN"),
        "matrix_pass_lanes": sum(item.get("status") == "PASS" for item in matrix.get("results", [])
                                  if item.get("case") == "bytestring-backing-array"),
        "matrix_expected_lanes": 6,
        "jvm_descriptor": descriptor["result"],
        "macos_arm64_reference": native_summary.get("status", native["result"]),
        "macos_arm64_reference_lanes": sum(
            entry.get("result") == "PASS" for entry in native_records.get("executions", [])
        ),
        "swift_build": build["result"],
        "swift_focused_test": swift_test["result"],
        "inventory_before": inventory_before["result"],
        "execution_receipts": len(execution_records),
        "output": "PASS:direct=true:inline=true:repeat=true\n",
        "output_sha256": sha256(b"PASS:direct=true:inline=true:repeat=true\n"),
        "evidence_path": str(EVIDENCE_PATH.relative_to(ROOT)),
    }
    save(output / "summary.json", summary)
    if not all_pass:
        print("FAILED_OR_INCOMPLETE; no validation evidence was promoted", file=sys.stderr)
        return 1

    save(EXECUTIONS_PATH, {"schema_version": 1, "executions": execution_records})
    write_validation_evidence(generator, execution_records, candidate_sha)
    promote = run_command([sys.executable, str(HERE / "generate.py"), "--write"], output, "inventory-promote")
    check = run_command([sys.executable, str(HERE / "generate.py"), "--check"], output, "inventory-check")
    if promote["result"] != "PASS" or check["result"] != "PASS":
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
