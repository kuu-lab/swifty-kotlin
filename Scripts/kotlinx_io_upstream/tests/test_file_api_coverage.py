import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("file_api_coverage", HERE / "files/promote_api_coverage.py")
coverage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage)


class FileAPICoverageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.addCleanup(self.temporary.cleanup)
        self.ledger = json.loads((HERE / "files/api-coverage.prepared.json").read_text())
        self.candidate = {key: "a" * (40 if key == "main_head" else 64) for key in coverage.FINGERPRINT_KEYS}
        self.ledger["candidate_fingerprint"] = self.candidate
        self.row = next(r for r in self.ledger["rows"] if r["scope"] == "COMMON_NATIVE")
        self.raw = self.root / "gate.raw"
        self.raw.write_bytes(b"actual normalized test result placeholder FOR UNIT TEST ONLY\n")

    def evidence(self, identifiers=None):
        identifiers = self.row["required_check_ids"] if identifiers is None else identifiers
        defs = {c["check_id"]: c for c in self.ledger["checks"]}
        receipt = {"candidate_fingerprint": self.candidate, "phase_exitcodes": {"gate": 0},
                   "inputs_unchanged": True, "reaped": True,
                   "checks": [{"check_id": c, "kind": defs[c]["kind"], "status": "PASS"} for c in identifiers],
                   "artifacts": [{"path": self.raw.name, "sha256": hashlib.sha256(self.raw.read_bytes()).hexdigest()}]}
        p = self.root / "receipt.json"
        p.write_text(json.dumps(receipt))
        return {"schema_version": 1, "candidate_fingerprint": self.candidate,
                "receipts": [{"check_id": c, "path": p.name, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for c in identifiers]}

    def test_unbound_preparation_stays_unverified_without_evidence(self):
        self.ledger["candidate_fingerprint"] = None
        result = coverage.promote(self.ledger, {"schema_version": 1, "receipts": []}, self.root)
        self.assertEqual(0, result["promoted_common_native_rows"])
        self.assertTrue(all(r["state"] == "UNVERIFIED" for r in result["rows"]))

    def test_complete_one_row_does_not_promote_unrelated_rows_or_jvm(self):
        result = coverage.promote(self.ledger, self.evidence(), self.root)
        self.assertEqual("PASS", next(r for r in result["rows"] if r["row_id"] == self.row["row_id"])["state"])
        self.assertEqual("UNVERIFIED", result["state"])
        self.assertTrue(all(r["state"] == "UNVERIFIED" for r in result["rows"] if r["scope"] == "JVM_COORDINATION"))

    def test_missing_required_check_keeps_row_unverified(self):
        result = coverage.promote(self.ledger, self.evidence(self.row["required_check_ids"][:-1]), self.root)
        self.assertEqual("UNVERIFIED", next(r for r in result["rows"] if r["row_id"] == self.row["row_id"])["state"])

    def test_old_candidate_receipt_rejected(self):
        e = self.evidence(); e["candidate_fingerprint"] = {**self.candidate, "compiler_sha256": "b" * 64}
        with self.assertRaisesRegex(ValueError, "stale"): coverage.promote(self.ledger, e, self.root)

    def test_compile_failure_cannot_promote_pass_labeled_checks(self):
        e = self.evidence(); p = self.root / "receipt.json"; r = json.loads(p.read_text());r["phase_exitcodes"]["gate"] = 1;p.write_text(json.dumps(r))
        for item in e["receipts"]: item["sha256"] = hashlib.sha256(p.read_bytes()).hexdigest()
        result = coverage.promote(self.ledger, e, self.root)
        self.assertEqual(0, result["promoted_common_native_rows"])

    def test_duplicate_check_receipt_rejected(self):
        e = self.evidence(); e["receipts"].append(e["receipts"][0])
        with self.assertRaisesRegex(ValueError, "duplicate"): coverage.promote(self.ledger, e, self.root)

    def test_receipt_hash_mutation_rejected(self):
        e = self.evidence(); (self.root / "receipt.json").write_text("{}")
        with self.assertRaisesRegex(ValueError, "hash"): coverage.promote(self.ledger, e, self.root)

    def test_raw_artifact_mutation_rejected(self):
        e = self.evidence(); self.raw.write_bytes(b"different candidate output")
        with self.assertRaisesRegex(ValueError, "artifact hash"): coverage.promote(self.ledger, e, self.root)

    def test_unknown_required_contract_check_rejected(self):
        self.row["required_check_ids"].append("invented.success")
        with self.assertRaisesRegex(ValueError, "unknown check"): coverage.promote(self.ledger, {"schema_version":1,"receipts":[]}, self.root)


if __name__ == "__main__": unittest.main()
