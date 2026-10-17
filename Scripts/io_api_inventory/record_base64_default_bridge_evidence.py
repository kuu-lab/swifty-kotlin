#!/usr/bin/env python3
"""Record KUU-2617 evidence from a passing F02 matrix and pinned JVM probe."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path

import generate
from probe_jvm_default_bridge_abi import REQUIRED_FLAGS, ROW_IDS


HERE = Path(__file__).resolve().parent
EXPECTED_CANDIDATE_SHA = "fd01a5e98145e8295e5b299b0a7190cc8d44e3a7"
CASE_ID = "base64-default-bridges"
LANES = (
    ("source", "O0"),
    ("source", "O2"),
    ("stdlib-library", "O0"),
    ("stdlib-library", "O2"),
    ("producer-consumer", "O0"),
    ("producer-consumer", "O2"),
)
ROW_CALLS = {
    "jvm-06eee316b84478d8": {
        "producer-default", "all-defaults", "default-end", "default-start",
        "explicit-range", "negative-start", "reversed-range",
    },
    "jvm-0a7391fd7c844ff7": {
        "producer-default", "all-defaults", "default-end", "default-start",
        "past-end", "reversed-range",
    },
    "jvm-1ba14d2113458d26": {
        "producer-default", "all-defaults", "default-end", "default-start",
        "past-end", "reversed-range",
    },
    "jvm-c376d0d1321523df": {
        "producer-default", "all-defaults", "default-destination-offset",
        "default-start", "default-end", "negative-destination-offset", "reversed-range",
    },
    "jvm-ebe766fdf289f961": {
        "producer-default", "all-defaults", "default-end", "default-start",
        "past-end", "reversed-range",
    },
}
ROW_TESTS = {
    "jvm-06eee316b84478d8": "testDecode",
    "jvm-0a7391fd7c844ff7": "testDecodeToByteString",
    "jvm-1ba14d2113458d26": "testByteArrayDecodeToByteString",
    "jvm-c376d0d1321523df": "testDecodeIntoByteArray",
    "jvm-ebe766fdf289f961": "testByteStringDecodeToByteString",
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def load_inventory_rows() -> dict[str, dict[str, str]]:
    with (HERE / "api-inventory.tsv").open(encoding="utf-8", newline="") as stream:
        rows = {row["row_id"]: row for row in csv.DictReader(stream, delimiter="\t")}
    require(set(ROW_IDS) <= rows.keys(), "one or more KUU-2617 rows are missing from api-inventory.tsv")
    return rows


def verify_matrix(matrix_path: Path, matrix: dict) -> tuple[Path, bytes, dict[tuple[str, str], Path]]:
    require(matrix.get("status") == "SELECTED_MATRIX_PASS", "F02 matrix did not pass")
    require(matrix.get("selected_cases") == [CASE_ID], "matrix must contain only the dedicated Base64 case")
    require(matrix.get("issue_complete") is False, "a selected subset must not claim full issue completion")
    require(matrix.get("candidate_sha") == EXPECTED_CANDIDATE_SHA,
            "matrix candidate SHA does not match the issue's pinned candidate")
    require(matrix.get("stdlib_origin") == "fresh CLI --stdlib-only process in this run",
            "matrix did not create a fresh stdlib KLIB in this run")

    source_root = Path(matrix["candidate_source_root"]).resolve()
    marker = source_root / ".codex-candidate-sha"
    require(marker.is_file(), "candidate source marker is missing")
    require(marker.read_text(encoding="utf-8").strip() == EXPECTED_CANDIDATE_SHA,
            "candidate source marker does not match the issue pin")
    require(digest(marker.read_bytes()) == matrix.get("candidate_marker_sha256"),
            "candidate source marker changed after the matrix run")
    require(digest((source_root / "Package.swift").read_bytes())
            == matrix.get("candidate_package_swift_sha256"),
            "candidate Package.swift changed after the matrix run")
    compiler_path = Path(matrix["compiler_path"]).resolve()
    require(compiler_path.is_relative_to(source_root), "matrix compiler is outside the pinned candidate source root")
    require(compiler_path.is_file() and digest(compiler_path.read_bytes()) == matrix.get("compiler_sha256"),
            "candidate compiler binary does not match the matrix receipt")

    expected_pairs = set(LANES)
    observed = {}
    for result in matrix.get("results", []):
        require(result.get("case") == CASE_ID, "matrix contains an unrelated case result")
        pair = (result.get("route"), result.get("optimization"))
        require(pair in expected_pairs and pair not in observed, f"unexpected or duplicate matrix lane: {pair}")
        require(result.get("status") == "PASS", f"matrix lane failed: {pair}")
        require(result.get("reference_kind") == "jvm", f"lane has no pinned JVM reference: {pair}")
        observed[pair] = result
    require(set(observed) == expected_pairs, "matrix is missing one or more required lanes")

    case_directory = matrix_path.resolve().parent / CASE_ID
    reference_stdout = (case_directory / "reference-run.stdout").read_bytes()
    require(not (case_directory / "reference-run.stderr").read_bytes(), "pinned JVM reference emitted stderr")
    reference_run = read_json(case_directory / "reference-run.json")
    require(reference_run.get("status") == "EXITED" and reference_run.get("exitcode") == 0,
            "pinned JVM reference did not exit successfully")
    lanes = {}
    for pair in LANES:
        directory = case_directory / f"{pair[0]}-{pair[1]}"
        stdout = (directory / "run.stdout").read_bytes()
        require(not (directory / "run.stderr").read_bytes(), f"candidate emitted stderr in {pair}")
        require(stdout == reference_stdout, f"candidate output differs from pinned JVM in {pair}")
        require(digest(stdout) == observed[pair]["stdout_sha256"], f"lane stdout hash mismatch in {pair}")
        require(digest(reference_stdout) == observed[pair]["normalized_stdout_sha256"],
                f"normalized output hash mismatch in {pair}")
        lanes[pair] = directory
    return case_directory, reference_stdout, lanes


def row_output(stdout: bytes, row_id: str) -> bytes:
    prefix = f"PASS:{row_id}:".encode("ascii")
    lines = [line for line in stdout.splitlines(keepends=True) if line.startswith(prefix)]
    calls = [line[len(prefix):].split(b":", 1)[0].decode("ascii") for line in lines]
    expected = ROW_CALLS[row_id]
    require(len(lines) == len(expected) and set(calls) == expected,
            f"assertion output is missing, duplicated, or unrelated for {row_id}: {calls}")
    return b"".join(lines)


def result(execution_id: str, output: bytes, count: int) -> dict:
    return {
        "execution_id": execution_id,
        "result": "PASS",
        "exit_code": 0,
        "stdout_sha256": digest(output),
        "stderr_sha256": digest(b""),
        "output_count": count,
    }


def build_records(matrix_path: Path, probe_path: Path) -> list[dict]:
    matrix = read_json(matrix_path)
    _, reference_stdout, lane_directories = verify_matrix(matrix_path, matrix)
    probe = read_json(probe_path)
    lock = read_json(generate.LOCK_PATH)
    artifact = next((item for item in lock["mavenArtifacts"]
                     if item["coordinate"].startswith("org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:")), None)
    require(artifact is not None, "pinned bytestring JVM artifact is missing from upstream-lock.json")
    require(probe.get("schema_version") == 1, "unsupported JVM probe receipt schema")
    require(probe.get("reference", {}).get("tag") == lock["tag"]
            and probe.get("reference", {}).get("commit") == lock["commit"],
            "JVM probe used a different upstream pin")
    require(probe.get("reference", {}).get("artifact_sha256") == artifact["sha256"],
            "JVM probe artifact hash differs from the locked reference")
    probe_rows = {entry["row_id"]: entry for entry in probe.get("results", [])}
    require(set(probe_rows) == set(ROW_IDS), "JVM probe receipt does not contain exactly the five target rows")

    inventory_rows = load_inventory_rows()
    records = []
    for row_id in ROW_IDS:
        row = inventory_rows[row_id]
        require(row["status"] == "unverified", f"expected {row_id} to await evidence")
        require(row["upstream_test_refs"] == f"bytestring/common/test/ByteStringBase64Test.kt#{ROW_TESTS[row_id]}",
                f"unexpected direct upstream test mapping for {row_id}")
        require(generate.validation_obligations(row) == ["jvm-descriptor", "native-default-dispatch"],
                f"unexpected compatibility obligations for {row_id}")

        jvm = probe_rows[row_id]
        require(set(jvm.get("flags", [])) == REQUIRED_FLAGS, f"unexpected physical JVM flags for {row_id}")
        require(jvm.get("output_count") == 1 and jvm.get("stderr_sha256") == digest(b""),
                f"invalid physical JVM probe output for {row_id}")
        descriptor_execution = {
            "case_id": row["upstream_test_refs"],
            "lane": "jvm-descriptor",
            "reference": {
                "execution_id": f"kuu-2617:pinned-jvm-classfile:{row_id}",
                "result": "PASS",
                "exit_code": 0,
                "stdout_sha256": jvm["stdout_sha256"],
                "stderr_sha256": jvm["stderr_sha256"],
                "output_count": jvm["output_count"],
            },
            "candidate": None,
        }
        row_stdout = row_output(reference_stdout, row_id)
        count = len(ROW_CALLS[row_id])
        executions = [descriptor_execution]
        for route, optimization in LANES:
            lane = f"{route}-{optimization}"
            output = row_output((lane_directories[(route, optimization)] / "run.stdout").read_bytes(), row_id)
            require(output == row_stdout, f"row output differs from its pinned JVM output in {lane}: {row_id}")
            executions.append({
                "case_id": row["upstream_test_refs"],
                "lane": lane,
                "reference": result(f"kuu-2617:reference:{lane}:{row_id}", row_stdout, count),
                "candidate": result(f"kuu-2617:candidate:{lane}:{row_id}", output, count),
            })

        records.append({
            "row_id": row_id,
            "candidate_sha": matrix["candidate_sha"],
            "reference_version": lock["tag"],
            "reference_commit": lock["commit"],
            **generate.validation_input_hashes(row),
            "compatibility_obligations": generate.validation_obligations(row),
            "executions": executions,
        })
    return records


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix", type=Path, required=True, help="passing run_f02_matrix.py summary.json")
    parser.add_argument("--jvm-probe", type=Path, required=True, help="probe_jvm_default_bridge_abi.py JSON receipt")
    parser.add_argument("--evidence", type=Path, default=generate.VALIDATION_EVIDENCE_PATH)
    args = parser.parse_args(argv)
    try:
        new_records = build_records(args.matrix, args.jvm_probe)
        existing = read_json(args.evidence)
        require(existing.get("schema_version") == generate.VALIDATION_EVIDENCE_SCHEMA_VERSION,
                "unsupported validation evidence schema")
        records = existing.get("records")
        require(isinstance(records, list), "validation evidence records must be an array")
        target_ids = set(ROW_IDS)
        preserved = [record for record in records if record.get("row_id") not in target_ids]
        merged = sorted([*preserved, *new_records], key=lambda record: record["row_id"])
        temporary = args.evidence.with_suffix(args.evidence.suffix + ".tmp")
        temporary.write_text(json.dumps({
            "schema_version": generate.VALIDATION_EVIDENCE_SCHEMA_VERSION,
            "records": merged,
        }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        temporary.replace(args.evidence)
        print(f"Recorded {len(new_records)} KUU-2617 rows in {args.evidence}")
        return 0
    except (OSError, KeyError, json.JSONDecodeError, ValueError) as error:
        parser.exit(1, f"KUU-2617 evidence was not recorded: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
