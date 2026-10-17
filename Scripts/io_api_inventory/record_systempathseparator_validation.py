#!/usr/bin/env python3
"""Record the focused KUU-2641 consumer and JVM-reference probe receipts."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

import generate
import run_f02_matrix
import run_systempathseparator_jvm_abi_probe

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
REFERENCE_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"
SOURCE_CASE_ID = (
    "Scripts/io_api_inventory/probes/systempathseparator/"
    "SystemPathSeparatorBindingProbe.kt#systemPathSeparatorBinding"
)
JVM_CASE_ID = (
    "Scripts/io_api_inventory/probes/systempathseparator/"
    "SystemPathSeparatorJvmAbiProbe.java#main"
)
SOURCE_CASE = "systempathseparator-binding"
SOURCE_ROW_IDS = ("klib-1cea0040ddde9cf5", "klib-e375bc5c05e11b68")
JVM_ROW_ID = "jvm-a1d46eb1f6c5e933"
DIRTY_PATCH_SHA256 = hashlib.sha256(b"").hexdigest()
REQUIRED_LANES = (
    ("source", "O0"),
    ("source", "O2"),
    ("stdlib-library", "O0"),
    ("stdlib-library", "O2"),
    ("producer-consumer", "O0"),
    ("producer-consumer", "O2"),
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def execution_id(subject: str, case_id: str, lane: str, candidate_sha: str, stdout_sha256: str) -> str:
    identity = "|".join((subject, case_id, lane, candidate_sha, stdout_sha256))
    return f"kuu2641-{subject}-{sha256_bytes(identity.encode())[:24]}"


def passing_execution(subject: str, case_id: str, lane: str, candidate_sha: str,
                      stdout: bytes, normalized_stdout: bytes, stderr: bytes,
                      probe_input_sha256: str) -> dict:
    return {
        "execution_id": execution_id(subject, case_id, lane, candidate_sha, sha256_bytes(stdout)),
        "case_id": case_id,
        "lane": lane,
        "result": "PASS",
        "exit_code": 0,
        "stdout_sha256": sha256_bytes(stdout),
        "normalized_stdout_sha256": sha256_bytes(normalized_stdout),
        "stderr_sha256": sha256_bytes(stderr),
        "probe_input_sha256": probe_input_sha256,
        "candidate_sha": candidate_sha,
        "reference_commit": REFERENCE_COMMIT,
    }


def load_rows() -> dict[str, dict[str, str]]:
    with (HERE / "api-inventory.tsv").open(encoding="utf-8", newline="") as source:
        return {row["row_id"]: row for row in csv.DictReader(source, delimiter="\t")}


def validate_matrix(output: Path, candidate_sha: str) -> tuple[list[dict], list[dict]]:
    summary_path = output / "summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    if summary.get("status") != "SELECTED_MATRIX_PASS":
        raise RuntimeError("the selected F02 matrix did not pass")
    if summary.get("selected_cases") != [SOURCE_CASE]:
        raise RuntimeError("the F02 run must select only systempathseparator-binding")
    if summary.get("workspace_git_sha") != candidate_sha:
        raise RuntimeError("the F02 run was not produced from the requested candidate SHA")
    if summary.get("dirty_patch_sha256") != DIRTY_PATCH_SHA256:
        raise RuntimeError("the F02 candidate worktree was dirty during execution")
    if summary.get("reference_commit") not in (None, REFERENCE_COMMIT):
        raise RuntimeError("the F02 run used a different upstream reference")

    results = [result for result in summary.get("results", []) if result.get("case") == SOURCE_CASE]
    if len(results) != len(REQUIRED_LANES):
        raise RuntimeError("the focused F02 run does not contain all six required lanes")
    if any(result.get("probe_case_id") != SOURCE_CASE_ID or result.get("status") != "PASS" for result in results):
        raise RuntimeError("the focused F02 run is missing a direct passing probe result")
    probe_path = REPO / "Scripts/io_api_inventory/probes/systempathseparator/SystemPathSeparatorBindingProbe.kt"
    probe_input_sha256 = sha256_file(probe_path)
    if summary.get("scenario_files_sha256", {}).get(probe_path.relative_to(REPO).as_posix()) != probe_input_sha256:
        raise RuntimeError("the F02 summary does not pin the direct Kotlin probe input")
    by_lane = {(result.get("route"), result.get("optimization")): result for result in results}
    if len(by_lane) != len(REQUIRED_LANES) or set(by_lane) != set(REQUIRED_LANES):
        raise RuntimeError("the focused F02 run has duplicate or missing lanes")

    case_dir = output / SOURCE_CASE
    reference_stdout_path = case_dir / "reference-run.stdout"
    reference_stderr_path = case_dir / "reference-run.stderr"
    reference_workspace = case_dir / "reference-run-work"
    raw_reference_stdout = reference_stdout_path.read_bytes()
    reference_stderr = reference_stderr_path.read_bytes()
    if reference_stderr:
        raise RuntimeError("the pinned JVM reference wrote stderr")
    normalized_reference = run_f02_matrix.normalized_paths(raw_reference_stdout, reference_workspace)
    reference_entries = []
    candidate_entries = []
    for route, optimization in REQUIRED_LANES:
        result = by_lane[(route, optimization)]
        lane = f"{route}-{optimization}"
        if result.get("expected_stdout_sha256") != sha256_bytes(normalized_reference):
            raise RuntimeError(f"reference stdout hash mismatch for {lane}")
        lane_dir = case_dir / lane
        raw_candidate_stdout = (lane_dir / "run.stdout").read_bytes()
        candidate_stderr = (lane_dir / "run.stderr").read_bytes()
        if candidate_stderr:
            raise RuntimeError(f"candidate wrote stderr in {lane}")
        normalized_candidate = run_f02_matrix.normalized_paths(raw_candidate_stdout, lane_dir / "run-work")
        if normalized_candidate != normalized_reference:
            raise RuntimeError(f"reference/candidate output mismatch in {lane}")
        if result.get("stdout_sha256") != sha256_bytes(raw_candidate_stdout):
            raise RuntimeError(f"candidate stdout hash mismatch for {lane}")
        if result.get("normalized_stdout_sha256") != sha256_bytes(normalized_candidate):
            raise RuntimeError(f"normalized candidate stdout hash mismatch for {lane}")
        reference_entries.append(passing_execution(
            "reference", SOURCE_CASE_ID, lane, candidate_sha,
            raw_reference_stdout, normalized_reference, reference_stderr, probe_input_sha256,
        ))
        candidate_entries.append(passing_execution(
            "candidate", SOURCE_CASE_ID, lane, candidate_sha,
            raw_candidate_stdout, normalized_candidate, candidate_stderr, probe_input_sha256,
        ))
    return reference_entries, candidate_entries


def validate_jvm_probe(output: Path, candidate_sha: str) -> dict:
    receipt = json.loads((output / "receipt.json").read_text(encoding="utf-8"))
    if (receipt.get("case_id"), receipt.get("candidate_sha"), receipt.get("reference_commit")) != (
        JVM_CASE_ID, candidate_sha, REFERENCE_COMMIT
    ):
        raise RuntimeError("JVM field probe receipt does not match the candidate and upstream pins")
    if (receipt.get("reference_only") is not True or receipt.get("result") != "PASS"
            or receipt.get("exit_code") != 0
            or receipt.get("candidate_jvm_emission") != (
                f"not-applicable: {run_systempathseparator_jvm_abi_probe.JVM_NATIVE_EMISSION_NOT_APPLICABLE}"
            )):
        raise RuntimeError("JVM field probe did not retain its reference-only boundary")
    stdout = (output / "probe.stdout").read_bytes()
    stderr = (output / "probe.stderr").read_bytes()
    if (stderr or sha256_bytes(stdout) != receipt.get("stdout_sha256")
            or sha256_bytes(stderr) != receipt.get("stderr_sha256")):
        raise RuntimeError("JVM field probe output does not match its receipt")
    if stdout.decode("utf-8").splitlines() != run_systempathseparator_jvm_abi_probe.EXPECTED_LINES:
        raise RuntimeError("JVM field probe output is not the expected direct assertion set")
    probe_input_sha256 = sha256_file(
        REPO / "Scripts/io_api_inventory/probes/systempathseparator/SystemPathSeparatorJvmAbiProbe.java"
    )
    if receipt.get("probe_input_sha256") != probe_input_sha256:
        raise RuntimeError("JVM field probe receipt does not pin the current direct probe input")
    return passing_execution(
        "reference", JVM_CASE_ID, "jvm-descriptor", candidate_sha,
        stdout, stdout, stderr, probe_input_sha256,
    )


def merge_catalog(existing: dict, case_ids: set[str], reference: list[dict], candidate: list[dict]) -> dict:
    for subject, additions in (("reference", reference), ("candidate", candidate)):
        retained = [entry for entry in existing.get(subject, []) if entry.get("case_id") not in case_ids]
        existing[subject] = sorted([*retained, *additions], key=lambda entry: (entry["case_id"], entry["lane"]))
    return existing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix-output", type=Path, required=True)
    parser.add_argument("--jvm-abi-output", type=Path, required=True)
    parser.add_argument("--candidate-sha", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", args.candidate_sha):
        parser.error("candidate SHA must be a full lowercase Git SHA")

    matrix_output = args.matrix_output.resolve()
    jvm_output = args.jvm_abi_output.resolve()
    reference_entries, candidate_entries = validate_matrix(matrix_output, args.candidate_sha)
    jvm_reference = validate_jvm_probe(jvm_output, args.candidate_sha)
    target_case_ids = {SOURCE_CASE_ID, JVM_CASE_ID}
    reference_entries.append(jvm_reference)

    catalog_path = HERE / "validation-probe-executions.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    if catalog.get("schema_version") != 1:
        raise RuntimeError("unsupported validation probe execution catalog")
    catalog = merge_catalog(catalog, target_case_ids, reference_entries, candidate_entries)

    rows = load_rows()
    evidence_path = HERE / "api-validation-evidence.json"
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    if evidence.get("schema_version") not in (1, generate.VALIDATION_EVIDENCE_SCHEMA_VERSION):
        raise RuntimeError("unsupported API validation evidence schema")
    evidence["schema_version"] = generate.VALIDATION_EVIDENCE_SCHEMA_VERSION
    retained_records = [record for record in evidence.get("records", [])
                        if record.get("row_id") not in {*SOURCE_ROW_IDS, JVM_ROW_ID}]
    probe_index = generate.validation_probe_index()
    source_reason = next(probe["candidate_not_applicable_reason"]
                         for probe in probe_index["probes"] if probe["case_id"] == JVM_CASE_ID)

    new_records = []
    for row_id in SOURCE_ROW_IDS:
        row = rows.get(row_id)
        if row is None:
            raise RuntimeError(f"missing target API row: {row_id}")
        executions = []
        for route, optimization in REQUIRED_LANES:
            lane = f"{route}-{optimization}"
            reference = next(entry for entry in reference_entries
                             if entry["case_id"] == SOURCE_CASE_ID and entry["lane"] == lane)
            candidate = next(entry for entry in candidate_entries
                             if entry["case_id"] == SOURCE_CASE_ID and entry["lane"] == lane)
            executions.append({
                "case_id": SOURCE_CASE_ID,
                "lane": lane,
                "reference": {key: reference[key] for key in ("execution_id", "result", "exit_code")},
                "candidate": {key: candidate[key] for key in ("execution_id", "result", "exit_code")},
            })
        new_records.append({
            "row_id": row_id,
            "candidate_sha": args.candidate_sha,
            "reference_version": "0.9.1",
            "reference_commit": REFERENCE_COMMIT,
            **generate.validation_input_hashes(row),
            "compatibility_obligations": generate.validation_obligations(row),
            "executions": executions,
        })

    row = rows.get(JVM_ROW_ID)
    if row is None:
        raise RuntimeError(f"missing target API row: {JVM_ROW_ID}")
    new_records.append({
        "row_id": JVM_ROW_ID,
        "candidate_sha": args.candidate_sha,
        "reference_version": "0.9.1",
        "reference_commit": REFERENCE_COMMIT,
        **generate.validation_input_hashes(row),
        "compatibility_obligations": generate.validation_obligations(row),
        "executions": [{
            "case_id": JVM_CASE_ID,
            "lane": "jvm-descriptor",
            "reference": {key: jvm_reference[key] for key in ("execution_id", "result", "exit_code")},
            "candidate": {
                "execution_id": None,
                "result": "NOT_APPLICABLE",
                "exit_code": None,
                "reason": source_reason,
            },
        }],
    })

    evidence["records"] = sorted([*retained_records, *new_records], key=lambda record: record["row_id"])
    write_json(catalog_path, catalog)
    write_json(evidence_path, evidence)
    inventory_lock_path = HERE / "upstream-lock.json"
    inventory_lock = json.loads(inventory_lock_path.read_text(encoding="utf-8"))
    inventory_lock["validationProbeRefsSha256"] = sha256_file(HERE / "validation-probe-refs.json")
    inventory_lock["validationProbeExecutionsSha256"] = sha256_file(catalog_path)
    write_json(inventory_lock_path, inventory_lock)
    subprocess.run([sys.executable, str(HERE / "generate.py"), "--write"], cwd=REPO, check=True)
    subprocess.run([sys.executable, str(HERE / "generate.py"), "--check"], cwd=REPO, check=True)
    print(json.dumps({
        "candidate_sha": args.candidate_sha,
        "source_rows": list(SOURCE_ROW_IDS),
        "source_lanes": [f"{route}-{optimization}" for route, optimization in REQUIRED_LANES],
        "jvm_row": JVM_ROW_ID,
        "jvm_descriptor_result": "PASS (official reference only; Native JVM emission is not applicable)",
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
