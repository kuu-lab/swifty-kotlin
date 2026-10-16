#!/usr/bin/env python3
"""Capture the pinned KUU-2584 ByteString declaration-shape matrix as evidence."""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
CASE_ID = "bytestring-declaration-shape"
TARGET_ROWS = {
    "jvm-30aa8296be3c5f34",
    "jvm-513421237a6901bd",
    "jvm-bbea794ad47ba10d",
    "klib-6ac82acec38abefe",
    "klib-b3c4163f48365984",
}
LANES = (
    "source-O0",
    "source-O2",
    "stdlib-library-O0",
    "stdlib-library-O2",
    "producer-consumer-O0",
    "producer-consumer-O2",
)
EXPECTED_OUTPUT = (
    "ByteString.compareTo:-1\n"
    "ByteString.Companion.public-type:true\n"
    "ByteString.Companion.singleton:true\n"
)
EXPECTED_REJECTIONS = ["ByteStringSubclassProbe", "ByteStringCompanionSubclassProbe"]
DIAGNOSTIC_MARKERS = ["final", *EXPECTED_REJECTIONS]


def digest_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def digest_file(path: Path) -> str:
    return digest_bytes(path.read_bytes())


def load_generator():
    spec = importlib.util.spec_from_file_location("io_inventory_generator", HERE / "generate.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object: {path}")
    return value


def require_receipt(directory: Path, name: str, exit_code: int) -> dict:
    receipt = load_json(directory / f"{name}.json")
    if receipt.get("status") != "EXITED" or receipt.get("exitcode") != exit_code:
        raise ValueError(f"unexpected {name} receipt in {directory}")
    return receipt


def verify_negative(directory: Path, prefix: str, expected_source_sha256: str | None = None) -> dict:
    receipt = require_receipt(directory, prefix, 1)
    stdout = (directory / f"{prefix}.stdout").read_bytes()
    stderr = (directory / f"{prefix}.stderr").read_bytes()
    diagnostic = stdout + stderr
    text = diagnostic.decode("utf-8", errors="replace").lower()
    if any(marker.lower() not in text for marker in DIAGNOSTIC_MARKERS):
        raise ValueError(f"{prefix} did not report both expected declaration rejections")
    source_path = directory / "inputs/Negative.kt"
    source_sha256 = digest_file(source_path)
    if expected_source_sha256 is not None and source_sha256 != expected_source_sha256:
        raise ValueError(f"staged negative source hash differs in {directory}")
    if receipt.get("stdout_sha256") != digest_bytes(stdout) or receipt.get("stderr_sha256") != digest_bytes(stderr):
        raise ValueError(f"{prefix} stream hash mismatch in {directory}")
    return {
        "result": "EXPECTED_REJECTION",
        "exit_code": 1,
        "source_sha256": source_sha256,
        "diagnostic_sha256": digest_bytes(diagnostic),
        "rejected_declarations": EXPECTED_REJECTIONS,
    }


def capture(summary_path: Path) -> list[dict]:
    generator = load_generator()
    summary_path = summary_path.resolve()
    run_root = summary_path.parent
    summary_bytes = summary_path.read_bytes()
    summary = load_json(summary_path)
    if summary.get("status") != "SELECTED_MATRIX_PASS":
        raise ValueError("the selected declaration-shape matrix did not pass")
    if summary.get("workspace_git_sha") != generator.KUU2584_CANDIDATE_SHA:
        raise ValueError("the matrix candidate SHA does not match KUU-2584")
    if summary.get("selected_cases") != [CASE_ID] or summary.get("issue_complete") is not False:
        raise ValueError("the summary is not the focused ByteString declaration-shape run")
    if summary.get("stdlib_origin") != "fresh CLI --stdlib-only process in this run":
        raise ValueError("the matrix did not build a fresh KSwiftK stdlib artifact")

    results = summary.get("results")
    if not isinstance(results, list) or len(results) != len(LANES):
        raise ValueError("the matrix summary does not contain exactly six candidate lanes")
    by_lane = {}
    for result in results:
        if not isinstance(result, dict):
            raise ValueError("malformed candidate lane result")
        lane = f"{result.get('route')}-{result.get('optimization')}"
        if lane in by_lane or result.get("case") != CASE_ID or result.get("status") != "PASS":
            raise ValueError(f"non-passing or duplicate candidate lane: {lane}")
        if result.get("api_row_ids") != sorted(TARGET_ROWS):
            raise ValueError(f"candidate lane does not cover the exact five rows: {lane}")
        by_lane[lane] = result
    if set(by_lane) != set(LANES):
        raise ValueError("one or more required candidate lanes are missing")

    expected = EXPECTED_OUTPUT.encode("utf-8")
    expected_sha256 = digest_bytes(expected)
    case_dir = run_root / CASE_ID
    reference_output = (case_dir / "reference-run.stdout").read_bytes()
    if reference_output != expected or (case_dir / "reference-run.stderr").read_bytes():
        raise ValueError("pinned JVM reference output differs from the recorded expected output")
    require_receipt(case_dir, "reference-compile", 0)
    reference_run = require_receipt(case_dir, "reference-run", 0)
    if reference_run.get("stdout_sha256") != expected_sha256:
        raise ValueError("pinned JVM reference output receipt hash mismatch")
    reference_negative = verify_negative(case_dir, "reference-negative-compile")

    shape_checks = summary.get("reference_shape_checks", {}).get(CASE_ID, {})
    jvm_row_ids = ["jvm-30aa8296be3c5f34", "jvm-513421237a6901bd", "jvm-bbea794ad47ba10d"]
    native_row_ids = ["klib-6ac82acec38abefe", "klib-b3c4163f48365984"]
    if shape_checks.get("api_row_ids") != jvm_row_ids:
        raise ValueError("pinned JVM ABI inspection did not cover the exact three JVM rows")
    native_checks = shape_checks.get("native_klib", {})
    if native_checks.get("api_row_ids") != native_row_ids:
        raise ValueError("pinned Native KLIB inspection did not cover the exact two KLIB rows")
    jvm_class_receipt = require_receipt(case_dir, "jvm-byte-string-class", 0)
    jvm_companion_receipt = require_receipt(case_dir, "jvm-byte-string-companion", 0)
    native_metadata_receipt = require_receipt(case_dir, "native-byte-string-metadata", 0)
    native_abi_receipt = require_receipt(case_dir, "native-byte-string-abi", 0)
    if jvm_class_receipt.get("stdout_sha256") is None or jvm_companion_receipt.get("stdout_sha256") is None:
        raise ValueError("pinned JVM javap output hashes are missing")
    if (native_metadata_receipt.get("stdout_sha256") != native_checks.get("metadata_sha256")
            or native_abi_receipt.get("stdout_sha256") != native_checks.get("abi_sha256")):
        raise ValueError("pinned Native KLIB output receipts disagree with the matrix summary")

    lock = load_json(REPO / "Scripts/kotlinx_io_upstream/reference-lock.json")
    jvm_artifact = next(item for item in lock["jvm_artifacts"]
                        if item["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:0.9.1")
    native_artifact = next(item for item in lock["native_artifacts"]
                           if item["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-bytestring-macosarm64:0.9.1")
    native_archive = lock["native_compiler_archives"]["macos_arm64"]
    reference_artifacts = {
        "jvm_artifact_sha256": jvm_artifact["sha256"],
        "native_klib_sha256": native_artifact["sha256"],
        "native_compiler_archive_sha256": native_archive["sha256"],
        "native_klib_tool_sha256": native_checks["klib_tool_sha256"],
    }
    if (shape_checks.get("reference_jar_sha256") != jvm_artifact["sha256"]
            or native_checks.get("reference_klib_sha256") != native_artifact["sha256"]
            or native_checks.get("native_compiler_archive_sha256") != native_archive["sha256"]):
        raise ValueError("reference JVM/Native artifacts do not match their lock")

    lane_outputs = {}
    negative_probes = {}
    executions = []
    source_hashes = set()
    for lane in LANES:
        result = by_lane[lane]
        lane_dir = case_dir / lane
        require_receipt(lane_dir, "consumer", 0)
        run_receipt = require_receipt(lane_dir, "run", 0)
        observed = (lane_dir / "run.stdout").read_bytes()
        if observed != expected or (lane_dir / "run.stderr").read_bytes():
            raise ValueError(f"candidate output differs from the reference in {lane}")
        if (result.get("stdout_sha256") != expected_sha256
                or result.get("normalized_stdout_sha256") != expected_sha256
                or run_receipt.get("stdout_sha256") != expected_sha256):
            raise ValueError(f"candidate output receipt hash mismatch in {lane}")
        negative_probe = verify_negative(lane_dir, "negative-compile")
        summary_negative = result.get("negative_compile")
        if (not isinstance(summary_negative, dict)
                or summary_negative.get("exit_code") != negative_probe["exit_code"]
                or summary_negative.get("source_sha256") != negative_probe["source_sha256"]
                or summary_negative.get("diagnostic_sha256") != negative_probe["diagnostic_sha256"]):
            raise ValueError(f"negative compile receipt differs from the summary in {lane}")
        source_hashes.add(negative_probe["source_sha256"])
        lane_outputs[lane] = {
            "stdout_sha256": digest_bytes(observed),
            "normalized_stdout_sha256": result["normalized_stdout_sha256"],
            "stdout_bytes": len(observed),
        }
        negative_probes[lane] = negative_probe
        executions.append({
            "case_id": CASE_ID,
            "lane": lane,
            "reference": {
                "execution_id": f"reference:jvm:{CASE_ID}:{digest_bytes(summary_bytes)[:12]}",
                "result": "PASS",
                "exit_code": 0,
            },
            "candidate": {
                "execution_id": f"candidate:{summary['workspace_git_sha']}:{lane}:{digest_bytes(summary_bytes)[:12]}",
                "result": "PASS",
                "exit_code": 0,
            },
        })
    if len(source_hashes) != 1:
        raise ValueError("candidate negative probe input changed between lanes")

    origin_inputs = {
        relative: digest_file(generator.UPSTREAM / relative)
        for relative in generator.BYTESTRING_DECLARATION_SHAPE_ORIGIN_INPUTS
    }
    probe_inputs = {
        relative: digest_file(REPO / relative)
        for relative in generator.BYTESTRING_DECLARATION_SHAPE_PROBE_INPUTS
    }
    ref_checks = {
        "jvm_positive": {
            "execution_id": f"reference:jvm:{CASE_ID}:{digest_bytes(summary_bytes)[:12]}",
            "result": "PASS",
            "exit_code": 0,
            "stdout_sha256": digest_bytes(reference_output),
            "stdout_bytes": len(reference_output),
        },
        "jvm_negative": {
            "execution_id": f"reference:jvm-negative:{CASE_ID}:{digest_bytes(summary_bytes)[:12]}",
            **reference_negative,
        },
        "jvm_abi": {
            "result": "PASS",
            "api_row_ids": jvm_row_ids,
            "byte_string_stdout_sha256": jvm_class_receipt["stdout_sha256"],
            "companion_stdout_sha256": jvm_companion_receipt["stdout_sha256"],
        },
        "native_klib": {
            "result": "PASS",
            "api_row_ids": native_row_ids,
            "metadata_stdout_sha256": native_metadata_receipt["stdout_sha256"],
            "abi_stdout_sha256": native_abi_receipt["stdout_sha256"],
        },
    }
    input_rows = {}
    with generator.LEDGER_PATH.open(encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            if row.get("row_id") in TARGET_ROWS:
                input_rows[row["row_id"]] = row
    if set(input_rows) != TARGET_ROWS:
        raise ValueError("the generated API ledger does not contain the exact five target rows")

    records = []
    for row_id in sorted(TARGET_ROWS):
        row = input_rows[row_id]
        record = {
            "row_id": row_id,
            "candidate_sha": summary["workspace_git_sha"],
            "reference_version": "0.9.1",
            "reference_commit": generator.EXPECTED_TAG_COMMIT,
            **generator.validation_input_hashes(row),
            "compatibility_obligations": ["declaration-shape"],
            "case_id": CASE_ID,
            "assertion": generator.BYTESTRING_DECLARATION_SHAPE_ASSERTIONS[row_id],
            "assertion_count": 1,
            "target_row_count": len(TARGET_ROWS),
            "candidate_lane_count": len(LANES),
            "expected_output": EXPECTED_OUTPUT,
            "expected_output_sha256": expected_sha256,
            "expected_output_bytes": len(expected),
            "candidate_compiler_sha256": summary["compiler_sha256"],
            "matrix_summary_sha256": digest_bytes(summary_bytes),
            "matrix_dirty_patch_sha256": summary["dirty_patch_sha256"],
            "fresh_stdlib_manifest_sha256": summary["stdlib_files_sha256"]["manifest.json"],
            "origin_input_sha256": origin_inputs,
            "probe_input_sha256": probe_inputs,
            "reference_artifacts": reference_artifacts,
            "reference_checks": ref_checks,
            "executions": executions,
            "lane_outputs": lane_outputs,
            "negative_probes": negative_probes,
        }
        records.append(record)
    return records


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--summary", type=Path, required=True, help="successful focused F02 summary.json")
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--write", action="store_true", help="write declaration_shape_records into the evidence file")
    action.add_argument("--check", action="store_true", help="compare captured evidence with the evidence file")
    args = parser.parse_args(argv)

    try:
        records = capture(args.summary)
        generator = load_generator()
        evidence_path = generator.VALIDATION_EVIDENCE_PATH
        evidence = load_json(evidence_path)
        ordinary_records = evidence.get("records", [])
        if not isinstance(ordinary_records, list):
            raise ValueError("api-validation-evidence records must be an array")
        expected = {
            "schema_version": generator.VALIDATION_EVIDENCE_SCHEMA_VERSION,
            "records": ordinary_records,
            "declaration_shape_records": records,
        }
        rendered = json.dumps(expected, indent=2, ensure_ascii=False) + "\n"
        if args.write:
            evidence_path.write_text(rendered, encoding="utf-8")
            print(f"Recorded {len(records)} KUU-2584 declaration-shape rows in {evidence_path.relative_to(REPO)}.")
        else:
            if evidence != expected:
                raise ValueError("declaration-shape evidence is stale; rerun with --write")
            print(f"OK KUU-2584 declaration-shape evidence: {len(records)} rows, {len(LANES)} lanes.")
    except (OSError, KeyError, TypeError, ValueError, StopIteration) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
