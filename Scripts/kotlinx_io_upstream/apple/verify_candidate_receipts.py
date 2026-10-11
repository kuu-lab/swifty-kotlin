#!/usr/bin/env python3
"""Admit only the exact Apple focused scope; never rewrite existing receipts.

The native helper records CommandResult strings encoded as UTF-8, not arbitrary
raw Native bytes. Swift process streams are retained separately by the runner.
A successful scoped receipt does not establish the outstanding ownership/SDK API
contracts documented in README.md.
"""
from pathlib import Path
import argparse
import hashlib
import json

ORIGINAL_LANES = {f"{mode}-original25-O{optimization}"
                  for mode in ("source", "stdlib-library", "producer-consumer")
                  for optimization in (0, 2)}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def verify(output, expected_file):
    terminal = json.loads((output / "terminal.json").read_text())
    require(terminal["status"] == "ALL_REQUESTED_STAGES_PASSED_PENDING_EVIDENCE_AUDIT",
            "Outer runner did not complete every requested stage")
    require(terminal.get("frozen_inputs_unchanged") is True
            and terminal.get("proof_capture_errors") == [], "Frozen-input/terminal proof incomplete")
    counts = json.loads((output / "all.test-counts.json").read_text())
    require({key: (value["methods"], value["cases"], value["suites"])
             for key, value in counts.items()} ==
            {"metadata": (1, 2, 1), "runtime": (4, 4, 1), "native": (4, 12, 1)},
            "Expected exact Core1/2 + Runtime4/4 + Backend4/12 scope")
    for stage in ("metadata", "runtime", "native"):
        log = "".join((output / (stage + suffix)).read_text(errors="replace")
                      for suffix in (".stdout", ".stderr"))
        require("Test process crash (retried)" not in log
                and "swift_test.sh: test process crashed with a signal" not in log,
                "A wrapper process-crash retry cannot become fresh candidate proof")
    expected = expected_file.read_bytes()
    lines = expected.splitlines()
    ids = [line.removeprefix(b"PASS ").decode("ascii") for line in lines if line.startswith(b"PASS ")]
    require(len(lines) == 50 and len(ids) == 25 and len(set(ids)) == 25,
            "Pinned original driver must contain exactly 25 unique BEGIN/PASS pairs")
    require(lines == [prefix + identifier.encode("ascii") for identifier in ids
                      for prefix in (b"BEGIN ", b"PASS ")], "Pinned BEGIN/PASS order differs")
    lanes = {}
    for receipt_file in sorted(output.glob("*.json")):
        proof = json.loads(receipt_file.read_text())
        # Toolchain/environment receipts also include JSON arrays.
        if not isinstance(proof, dict):
            continue
        lane = proof.get("lane")
        if lane not in ORIGINAL_LANES:
            continue
        require(lane not in lanes, "Duplicate original lane proof: " + lane)
        require(proof["status"] == "PASS_CLEANED" and proof["actual_exit"] == 0
                and proof["native_returned_after_exit"] is True
                and proof["stdout_exact"] is True and proof["stderr_empty"] is True,
                "Original lane did not finish every immutable/output check")
        require(proof["entryPointFQName"] == "kuu1763originalconsumer.main", "Wrong original entry")
        stdout = receipt_file.with_suffix(".stdout")
        stderr = receipt_file.with_suffix(".stderr")
        require(stdout.read_bytes() == expected and stderr.read_bytes() == b"", "Original output differs")
        require(proof["stdout_sha256"] == digest(stdout)
                and proof["expected_sha256"] == digest(expected_file), "Original output hashes differ")
        imported = not lane.startswith("source-")
        require((proof["stdlib_path"] != "SOURCE") == imported, "Source/library mode differs")
        if imported:
            require({"manifest.json", "metadata.bin"} <= proof["stdlib_full_hashes"].keys(),
                    "Actual imported stdlib snapshot missing")
        producer = lane.startswith("producer-consumer-")
        require((proof["producer_path"] != "NONE") == producer, "Producer boundary differs")
        if producer:
            require({"manifest.json", "metadata.bin"} <= proof["producer_full_hashes"].keys(),
                    "Actual independent producer snapshot missing")
        lanes[lane] = {"receipt": receipt_file.name, "receipt_sha256": digest(receipt_file),
                       "stdout_sha256": digest(stdout), "original_execution_ids": ids}
    require(lanes.keys() == ORIGINAL_LANES, "Missing exact six original lanes")
    return {"status": "SCOPED_OBSERVED_RECEIPTS_MATCH_PENDING_SPEC_AUDIT",
            "methods": 9, "cases": 18, "suites": 3, "original_lanes": lanes,
            "original_body_executions": 150,
            "native_output_encoding": "CommandResult String encoded as UTF-8",
            "remaining_API_callback_GC_lease_contracts_verified": False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--receipts", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    expected = root / "Tests/CompilerBackendTests/Fixtures/IOApple1763/originals.expected.stdout"
    result = verify(args.receipts.resolve(), expected)
    (args.receipts.resolve() / "workflow-admission.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
