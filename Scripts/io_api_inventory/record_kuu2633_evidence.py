#!/usr/bin/env python3
"""Assemble KUU-2633 row evidence from pinned JVM and native execution receipts."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
OUTPUT = HERE / "kuu-2633-evidence.json"
TARGET_ROWS = {
    "jvm-29a01d1deaf3b966": "klib-8f2cd67956fefb8b",
    "jvm-32ddc189d171b174": "klib-b33ce5b385a93879",
    "jvm-5c5fb6c81ee3a3b9": "klib-001cc19c43da51fc",
    "jvm-b88878973d5558f7": "klib-5864c1c328005421",
}
EXPECTED_LANES = {
    ("source", "O0"): "source-O0",
    ("source", "O2"): "source-O2",
    ("producer-library", "O0"): "producer-consumer-O0",
    ("producer-library", "O2"): "producer-consumer-O2",
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_generator():
    spec = importlib.util.spec_from_file_location("io_inventory_generator", HERE / "generate.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def receipt(args) -> dict:
    if not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", args.candidate_sha):
        raise SystemExit("candidate SHA must be a full 40- or 64-character lowercase hexadecimal SHA")
    reference = json.loads(args.jvm_reference.read_text(encoding="utf-8"))
    if reference.get("issue") != "KUU-2633" or reference.get("reference", {}).get("result") != "PASS":
        raise SystemExit("JVM reference receipt is not a passing KUU-2633 probe")
    reference_data = reference["reference"]
    if (reference_data.get("kotlin_version"), reference_data.get("kotlinx_io_version"),
            reference_data.get("upstream_commit")) != (
        "2.3.10", "0.9.1", "362bdc35e159bad6da1e08101c8321792d762281"
    ):
        raise SystemExit("JVM reference receipt does not match the pinned compiler/library/source")

    generator = load_generator()
    lock, rows, _ = generator.build_outputs()
    by_id = {row["row_id"]: row for row in rows}
    if not set(TARGET_ROWS).issubset(by_id):
        raise SystemExit("KUU-2633 target rows are missing from generated inventory")
    source_by_id = {row["row_id"]: row for row in rows}
    reference_abi = {row["row_id"]: row for row in reference_data.get("abi", [])}
    if set(reference_abi) != set(TARGET_ROWS):
        raise SystemExit("JVM reference receipt does not contain exactly the four target ABI rows")

    fixture_dir = REPO / "Tests/CompilerBackendTests/Fixtures/IOIndexOfDefault2633"
    fixture_hashes = {
        path.name: digest(path.read_bytes())
        for path in (fixture_dir / "producer.kt", fixture_dir / "consumer.kt", fixture_dir / "expected.stdout")
    }
    if reference_data.get("fixture_sha256") != fixture_hashes:
        raise SystemExit("JVM reference probe was not run against the current dedicated fixture")
    expected_stdout = (fixture_dir / "expected.stdout").read_bytes()
    proofs = []
    for proof_path in sorted(args.native_evidence.rglob("success-proof.json")):
        proof = json.loads(proof_path.read_text(encoding="utf-8"))
        if proof.get("issue") == "KUU-2633" and proof.get("fixture") == "kuu2633-indexof-default-bridges":
            proofs.append((proof_path.parent, proof))
    proof_by_lane = {}
    for root, proof in proofs:
        lane = (proof.get("source_or_library"), proof.get("optimization"))
        if lane not in EXPECTED_LANES or lane in proof_by_lane:
            raise SystemExit(f"duplicate or unexpected KUU-2633 candidate lane: {lane}")
        if proof.get("status") != "PASS" or proof.get("command_exit_code") != 0 or proof.get("stdout_exact_match") is not True:
            raise SystemExit(f"KUU-2633 candidate lane did not pass: {root}")
        if proof.get("candidate_sha") != args.candidate_sha:
            raise SystemExit(f"candidate SHA mismatch in execution receipt: {root}")
        actual_stdout = (root / "run.stdout.utf8").read_bytes()
        actual_stderr = (root / "run.stderr.utf8").read_bytes()
        if actual_stdout != expected_stdout or actual_stderr:
            raise SystemExit(f"retained KUU-2633 output differs from the pinned expectation: {root}")
        for input_name, field in (
            ("producer.kt", "producer_input_sha256"),
            ("consumer.kt", "consumer_input_sha256"),
            ("expected.stdout", "expected_sha256"),
        ):
            if digest((root / input_name).read_bytes()) != proof.get(field) or proof.get(field) != fixture_hashes[input_name]:
                raise SystemExit(f"KUU-2633 fixture hash mismatch for {input_name}: {root}")
        links = proof.get("target_default_stub_links")
        if proof["source_or_library"] == "producer-library":
            if not isinstance(links, dict) or set(links) != set(TARGET_ROWS) or not all(links.values()):
                raise SystemExit(f"fresh producer .kklib did not retain all four default-stub links: {root}")
            artifact_hashes = proof.get("producer_artifact_full_hashes")
            if not isinstance(artifact_hashes, dict) or not {"manifest.json", "metadata.bin"}.issubset(artifact_hashes):
                raise SystemExit(f"fresh producer .kklib hashes are incomplete: {root}")
            stdlib_hashes = proof.get("stdlib_artifact_full_hashes")
            if not isinstance(stdlib_hashes, dict) or not {"manifest.json", "metadata.bin"}.issubset(stdlib_hashes):
                raise SystemExit(f"candidate stdlib .kklib hashes are incomplete: {root}")
        elif links != {}:
            raise SystemExit(f"source lane unexpectedly reports library default-stub links: {root}")
        proof_by_lane[lane] = (root, proof)
    if set(proof_by_lane) != set(EXPECTED_LANES):
        raise SystemExit(f"missing KUU-2633 candidate lanes: {sorted(set(EXPECTED_LANES) - set(proof_by_lane))}")

    consumer_execution_id = "reference-kuu2633-kotlin-2.3.10-consumer"
    executions_by_row = {}
    records = []
    for row_id, source_row_id in TARGET_ROWS.items():
        row = by_id[row_id]
        source_row = source_by_id[source_row_id]
        jvm_row = reference_abi[row_id]
        if jvm_row.get("result") != "PASS" or jvm_row.get("descriptor") not in row["signature"]:
            raise SystemExit(f"pinned JVM descriptor receipt mismatch for {row_id}")
        if set(jvm_row.get("flags", [])) != {"ACC_PUBLIC", "ACC_STATIC", "ACC_SYNTHETIC"}:
            raise SystemExit(f"pinned JVM access flags mismatch for {row_id}")
        executions = [{
            "case_id": "Tests/CompilerBackendTests/Fixtures/IOIndexOfDefault2633/consumer.kt#main",
            "lane": "jvm-descriptor",
            "reference": {"execution_id": f"reference-javap-{row_id}", "result": "PASS", "exit_code": 0},
            "candidate": {"execution_id": "candidate-jvm-classfile-not-emitted", "result": "NOT_APPLICABLE", "exit_code": None},
        }]
        native_links = {}
        for lane_key, lane_name in EXPECTED_LANES.items():
            root, proof = proof_by_lane[lane_key]
            executions.append({
                "case_id": "Tests/CompilerBackendTests/Fixtures/IOIndexOfDefault2633/consumer.kt#main",
                "lane": lane_name,
                "reference": {"execution_id": consumer_execution_id, "result": "PASS", "exit_code": 0},
                "candidate": {"execution_id": f"candidate-{lane_name}-{root.name}", "result": "PASS", "exit_code": 0},
                "output_sha256": digest((root / "run.stdout.utf8").read_bytes()),
                "expected_stdout_sha256": fixture_hashes["expected.stdout"],
                "native_default_stub_link": proof.get("target_default_stub_links", {}).get(row_id),
                "producer_artifact_sha256": proof.get("producer_artifact_full_hashes"),
                "candidate_stdlib_artifact_sha256": proof.get("stdlib_artifact_full_hashes"),
            })
            if proof["source_or_library"] == "producer-library":
                native_links[lane_name] = proof["target_default_stub_links"][row_id]
        executions_by_row[row_id] = executions
        records.append({
            "row_id": row_id,
            "source_api_row_id": source_row_id,
            "candidate_sha": args.candidate_sha,
            "reference_version": lock["tag"],
            "reference_commit": lock["commit"],
            **generator.validation_input_hashes(row),
            "compatibility_obligations": [
                "jvm-reference-physical-descriptor",
                "native-default-dispatch",
                "native-default-behavior",
            ],
            "jvm_reference": jvm_row,
            "native_default_stub_links": native_links,
            "executions": executions,
            "candidate_physical_jvm_abi": "NOT_EMITTED_BY_KSWIFTK_NATIVE_TARGET",
            "ledger_status": row["status"],
            "source_contract": {
                "signature": source_row["signature"],
                "annotations": source_row["annotations"],
                "exception_contract": source_row["exception_contract"],
                "local_candidate_refs": source_row["local_candidate_refs"],
                "local_implementation_refs": source_row["local_implementation_refs"],
                "local_contract_differences": source_row["local_contract_differences"],
            },
        })
    return {
        "schema_version": 1,
        "issue": "KUU-2633",
        "evidence_format": "KUU-2469-compatible supplemental row evidence; does not promote a physical JVM ABI row",
        "candidate_sha": args.candidate_sha,
        "candidate_platform": "macOS native",
        "reference_version": lock["tag"],
        "reference_commit": lock["commit"],
        "reference_probe": {
            "kotlin_version": reference_data["kotlin_version"],
            "kotlinx_io_version": reference_data["kotlinx_io_version"],
            "maven_artifacts": {name: entry["sha256"] for name, entry in reference_data["maven_artifacts"].items()},
            "javap_version": reference_data["javap_version"],
            "consumer": reference_data["consumer"],
            "fixture_sha256": fixture_hashes,
            "result": "PASS",
        },
        "records": records,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate-sha", required=True)
    parser.add_argument("--jvm-reference", type=Path, required=True)
    parser.add_argument("--native-evidence", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--check", action="store_true", help="verify an existing receipt without writing")
    args = parser.parse_args()
    rendered = json.dumps(receipt(args), ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.check:
        if not args.output.is_file() or args.output.read_text(encoding="utf-8") != rendered:
            raise SystemExit(f"KUU-2633 evidence receipt is stale: {args.output}")
        print(f"OK KUU-2633 evidence receipt: {args.output}")
    else:
        args.output.write_text(rendered, encoding="utf-8")
        print(f"Wrote KUU-2633 evidence receipt: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
