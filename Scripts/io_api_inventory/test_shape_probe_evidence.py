#!/usr/bin/env python3
"""Check KUU-2582 direct probe evidence rejection paths."""

import copy
import csv
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent


def load_generator():
    spec = importlib.util.spec_from_file_location("io_inventory_generator", HERE / "generate.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ShapeProbeEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generator = load_generator()
        with (HERE / "api-inventory.tsv").open(encoding="utf-8", newline="") as stream:
            cls.rows = list(csv.DictReader(stream, delimiter="\t"))
        cls.lock = json.loads((HERE / "upstream-lock.json").read_text(encoding="utf-8"))
        cls.evidence = json.loads((HERE / "api-shape-probe-evidence.json").read_text(encoding="utf-8"))

    def _validate(self, evidence):
        with tempfile.TemporaryDirectory(prefix="kuu2582-shape-evidence-") as directory:
            path = Path(directory) / "evidence.json"
            path.write_text(json.dumps(evidence), encoding="utf-8")
            self.generator.validate_shape_probe_evidence(
                self.rows,
                self.lock,
                evidence_path=path,
            )

    def test_current_evidence_is_reproducible(self):
        self._validate(copy.deepcopy(self.evidence))

    def test_missing_lane_is_rejected(self):
        evidence = copy.deepcopy(self.evidence)
        evidence["executions"] = [
            item for item in evidence["executions"]
            if not (item["subject"] == "candidate" and item["lane"] == "producer-consumer-O2")
        ]
        with self.assertRaisesRegex(SystemExit, "missing shape probe executions"):
            self._validate(evidence)

    def test_stale_input_hash_is_rejected(self):
        evidence = copy.deepcopy(self.evidence)
        evidence["rows"][0]["test_input_sha256"] = "0" * 64
        with self.assertRaisesRegex(SystemExit, "stale test_input_sha256"):
            self._validate(evidence)

    def test_candidate_sha_must_match_ticket_baseline(self):
        evidence = copy.deepcopy(self.evidence)
        evidence["candidate_sha"] = "a" * 40
        with self.assertRaisesRegex(SystemExit, "issue's pinned candidate SHA"):
            self._validate(evidence)

    def test_output_hash_tampering_is_rejected(self):
        evidence = copy.deepcopy(self.evidence)
        lane = next(item for item in evidence["executions"] if item["lane"] == "source-O0")
        lane["output"] = "false\nfalse\n"
        with self.assertRaisesRegex(SystemExit, "output SHA-256 mismatch"):
            self._validate(evidence)

    def test_skipped_cases_are_rejected(self):
        evidence = copy.deepcopy(self.evidence)
        lane = next(item for item in evidence["executions"] if item["lane"] == "source-O2")
        lane["skipped_count"] = 1
        with self.assertRaisesRegex(SystemExit, "failure, skip, or unrun"):
            self._validate(evidence)

    def test_non_string_case_id_is_rejected(self):
        evidence = copy.deepcopy(self.evidence)
        lane = next(item for item in evidence["executions"] if item["lane"] == "source-O0")
        lane["case_ids"] = [{}]
        with self.assertRaisesRegex(SystemExit, "malformed case IDs"):
            self._validate(evidence)


if __name__ == "__main__":
    unittest.main()
