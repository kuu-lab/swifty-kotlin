#!/usr/bin/env python3
"""Persist KUU-2585 local-probe executions and their reproducible receipts."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import generate


ROW_IDS = (
    "jvm-7915e4861d081be6",
    "klib-48c0b12efeabdf13",
    "klib-8fe21b6650324264",
)
F02_CASE_ID = "unsafe-bytestring-api"
FOCUSED_TEST_COMMAND = (
    "bash Scripts/swift_test.sh --filter CompilerCoreTests.KotlinxIOUnsafeByteStringApiContractTests "
    "--no-parallel -Xswiftc -swift-version -Xswiftc 6"
)


def fail(message: str) -> None:
    raise SystemExit(f"UnsafeByteStringApi evidence error: {message}")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_sha(path: Path) -> str:
    return sha256(path.read_bytes())


def canonical_sha(value: object) -> str:
    data = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return sha256(data)


def repository_is_clean(candidate_sha: str) -> None:
    head = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    if head != candidate_sha:
        fail(f"matrix candidate {candidate_sha} is not current HEAD {head}")
    dirty = subprocess.check_output(["git", "-C", str(ROOT), "status", "--porcelain"], text=True)
    if dirty:
        fail("the checkout changed after the matrix and focused Sema test")


def load_summary(path: Path) -> dict:
    try:
        summary = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read F02 summary: {error}")
    if summary.get("status") != "SELECTED_MATRIX_PASS":
        fail("F02 summary is not a passing selected matrix")
    if summary.get("selected_cases") != [F02_CASE_ID] or summary.get("issue_complete") is not False:
        fail("F02 summary must contain only the UnsafeByteStringApi selected case")
    lanes = summary.get("results", [])
    expected_lanes = set(generate.LOCAL_NATIVE_PROBE_LANES)
    observed = {
        f"{entry.get('route')}-{entry.get('optimization')}": entry
        for entry in lanes
        if entry.get("case") == F02_CASE_ID
    }
    if set(observed) != expected_lanes or len(lanes) != len(expected_lanes):
        fail("F02 summary does not have the six distinct source/KLIB O0/O2 lanes")
    if any(entry.get("status") != "PASS" for entry in observed.values()):
        fail("F02 summary contains a non-passing lane")
    return summary


def lane_receipts(summary: dict, summary_path: Path, output: str) -> list[dict]:
    case_dir = summary_path.parent / F02_CASE_ID
    reference_stdout = case_dir / "reference-run.stdout"
    if not reference_stdout.is_file():
        fail("F02 reference stdout receipt is missing")
    reference_output = reference_stdout.read_bytes().decode("utf-8")
    if reference_output != output:
        fail("the pinned JVM output differs from the recorded expected output")
    reference_stdout_sha = file_sha(reference_stdout)
    reference_jar_sha = file_sha(case_dir / "reference.jar")
    stdlib_manifest_sha = summary.get("stdlib_files_sha256", {}).get("manifest.json")
    if not isinstance(stdlib_manifest_sha, str):
        fail("fresh stdlib manifest hash is missing from the F02 summary")

    result_by_lane = {
        f"{entry['route']}-{entry['optimization']}": entry
        for entry in summary["results"]
    }
    receipts = []
    for lane in generate.LOCAL_NATIVE_PROBE_LANES:
        result = result_by_lane[lane]
        if result.get("normalized_stdout_sha256") != reference_stdout_sha:
            fail(f"candidate output differs from the pinned JVM output in {lane}")
        artifacts = {
            "reference_jar": reference_jar_sha,
            "candidate_executable": result["executable_sha256"],
            "fresh_stdlib_manifest": stdlib_manifest_sha,
        }
        producer_files = result.get("producer_files_sha256")
        if producer_files:
            artifacts["producer_artifact_manifest"] = canonical_sha(producer_files)
        receipts.append({
            "case_id": "local:Scripts/diff_cases/kotlinx_io_unsafe_bytestring_api.kt#opt-in-use",
            "lane": lane,
            "status": "PASS",
            "reference_stdout_sha256": reference_stdout_sha,
            "candidate_stdout_sha256": result["normalized_stdout_sha256"],
            "artifacts_sha256": artifacts,
        })
    return receipts


def record_for_row(row: dict, summary: dict, summary_path: Path,
                   focused_stdout: Path, focused_stderr: Path) -> dict:
    candidate_sha = summary["workspace_git_sha"]
    if not re.fullmatch(r"[0-9a-f]{40}", candidate_sha):
        fail("F02 summary candidate SHA is malformed")
    repository_is_clean(candidate_sha)
    if summary.get("dirty_patch_sha256") != sha256(b""):
        fail("F02 matrix was not run from a clean candidate commit")

    local_refs = row["local_test_refs"].split(";")
    probe_hashes = {relative: file_sha(ROOT / relative) for relative in local_refs}
    harness_hashes = {
        relative: file_sha(ROOT / relative)
        for relative in sorted(generate.LOCAL_PROBE_RECEIPT_HARNESS_PATHS)
    }
    reference_hashes = {
        Path(path).name: digest
        for path, digest in summary.get("reference_sha256", {}).items()
    }
    for upstream_path in (
        "bytestring/common/src/unsafe/Annotations.kt",
        "bytestring/api/kotlinx-io-bytestring.api",
        "bytestring/api/kotlinx-io-bytestring.klib.api",
        "bytestring/common/test/ByteStringTest.kt",
    ):
        path = generate.UPSTREAM / upstream_path
        if path.is_file():
            reference_hashes[f"upstream:{upstream_path}"] = file_sha(path)

    case_specs = [
        (case_id, spec)
        for case_id, spec in generate.LOCAL_PROBE_EVIDENCE_CASES.items()
        if row["row_id"] in spec["row_ids"] and spec["path"] in local_refs
    ]
    executions = []
    for case_id, spec in case_specs:
        observed = [entry for entry in summary["local_probe_executions"] if entry["case_id"] == case_id]
        if {entry["lane"] for entry in observed} != set(spec["lanes"]):
            fail(f"missing registered local execution lanes for row {row['row_id']}")
        executions.extend({
            "case_id": entry["case_id"],
            "lane": entry["lane"],
            "reference": entry["reference"],
            "candidate": entry["candidate"],
        } for entry in observed)
    if not executions:
        fail(f"no local-probe execution records map to row {row['row_id']}")

    focused_output = focused_stdout.read_bytes()
    focused_error = focused_stderr.read_bytes()
    if (not re.search(
            rb"Test annotationShapeAndOptInDiagnosticsMatchSourceAndLibrary\(library:\) "
            rb"with 2 test cases passed",
            focused_output,
    ) or focused_error):
        fail("focused source/shared-KLIB Sema test did not report exactly two passing tests")
    focused_test = {
        "command": FOCUSED_TEST_COMMAND,
        "status": "PASS",
        "tests_passed": 2,
        "stdout_sha256": sha256(focused_output),
        "stderr_sha256": sha256(focused_error),
        "test_source_sha256": probe_hashes[generate.UNSAFE_BYTESTRING_API_SEMA_TEST],
    }

    is_jvm_row = row["representation"] == "JVM public ABI dump"
    if is_jvm_row:
        jvm_probe = summary.get("unsafe_byte_string_api_jvm_probe")
        source_metadata = summary.get("candidate_unsafe_byte_string_api_source_metadata")
        if not jvm_probe or jvm_probe.get("status") != "PASS" or not source_metadata:
            fail("JVM annotation bytecode or candidate source-metadata probe is missing")
        output = jvm_probe["output"]
        jvm_case_id = "local:Tests/CompilerCoreTests/Sema/KotlinxIOUnsafeByteStringApiContractTests.swift#jvm-annotation-shape"
        lane_receipt_values = [{
            "case_id": jvm_case_id,
            "lane": "jvm-descriptor",
            "status": "PASS",
            "reference_stdout_sha256": jvm_probe["stdout_sha256"],
            "candidate_stdout_sha256": canonical_sha(source_metadata),
            "artifacts_sha256": {
                "reference_bytestring_jar": jvm_probe["artifact_sha256"],
                "reference_javap": jvm_probe["tool_sha256"],
                "candidate_annotation_source": source_metadata["source_sha256"],
            },
        }]
        kind = "jvm-abi"
    else:
        output_file = summary_path.parent / F02_CASE_ID / "reference-run.stdout"
        output = output_file.read_bytes().decode("utf-8")
        lane_receipt_values = lane_receipts(summary, summary_path, output)
        kind = "f02-matrix"

    return {
        "row_id": row["row_id"],
        "candidate_sha": candidate_sha,
        "reference_version": summary.get("reference_version", "0.9.1"),
        "reference_commit": generate.EXPECTED_TAG_COMMIT,
        **generate.validation_input_hashes(row),
        "compatibility_obligations": generate.validation_obligations(row),
        "evidence_source": "local-probe",
        "executions": sorted(executions, key=lambda entry: (entry["lane"], entry["case_id"])),
        "run_receipts": {
            "kind": kind,
            "case_count": len({entry["case_id"] for entry in executions}),
            "probe_sha256": probe_hashes,
            "harness_sha256": harness_hashes,
            "reference_sha256": reference_hashes,
            "output": output,
            "output_sha256": sha256(output.encode("utf-8")),
            "lanes": sorted(lane_receipt_values, key=lambda entry: (entry["lane"], entry["case_id"])),
            "focused_test": focused_test,
        },
    }


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--focused-stdout", type=Path, required=True)
    parser.add_argument("--focused-stderr", type=Path, required=True)
    args = parser.parse_args(argv)
    summary_path = args.summary.resolve()
    summary = load_summary(summary_path)
    lock, rows, _ = generate.build_outputs()
    by_id = {row["row_id"]: row for row in rows}
    if any(row_id not in by_id for row_id in ROW_IDS):
        fail("one or more target API rows are absent from the generated inventory")
    records = [
        record_for_row(by_id[row_id], summary, summary_path, args.focused_stdout, args.focused_stderr)
        for row_id in ROW_IDS
    ]

    evidence_path = generate.VALIDATION_EVIDENCE_PATH
    original = evidence_path.read_text(encoding="utf-8")
    evidence = json.loads(original)
    if evidence.get("schema_version") != generate.VALIDATION_EVIDENCE_SCHEMA_VERSION:
        fail("the evidence file is not using the current KUU-2469 schema v2")
    preserved = [record for record in evidence["records"] if record.get("row_id") not in ROW_IDS]
    updated = {
        "schema_version": generate.VALIDATION_EVIDENCE_SCHEMA_VERSION,
        "records": sorted([*preserved, *records], key=lambda record: record["row_id"]),
    }
    evidence_path.write_text(json.dumps(updated, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    try:
        generate.build_outputs()
    except SystemExit:
        evidence_path.write_text(original, encoding="utf-8")
        raise
    print(f"Recorded {len(records)} UnsafeByteStringApi rows in {evidence_path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
