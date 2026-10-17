#!/usr/bin/env python3
"""Tests the KUU-2585 evidence recorder's matrix receipt validation."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import record_unsafe_bytestring_api_evidence as recorder
import generate


class UnsafeByteStringEvidenceRecorderTests(unittest.TestCase):
    def write_summary(self, results: list[dict]) -> Path:
        summary = {
            "status": "SELECTED_MATRIX_PASS",
            "selected_cases": [recorder.F02_CASE_ID],
            "issue_complete": False,
            "results": results,
        }
        directory = Path(tempfile.mkdtemp(prefix="kuu2585-recorder-"))
        path = directory / "summary.json"
        path.write_text(json.dumps(summary), encoding="utf-8")
        return path

    def passing_results(self) -> list[dict]:
        results = []
        for lane in generate.LOCAL_NATIVE_PROBE_LANES:
            route, optimization = lane.rsplit("-", 1)
            results.append({
                "case": recorder.F02_CASE_ID,
                "route": route,
                "optimization": optimization,
                "status": "PASS",
            })
        return results

    def test_load_summary_accepts_exact_six_passing_lanes(self):
        path = self.write_summary(self.passing_results())
        self.assertEqual(recorder.load_summary(path)["selected_cases"], [recorder.F02_CASE_ID])

    def test_load_summary_rejects_missing_or_failing_lane(self):
        results = self.passing_results()
        results.pop()
        path = self.write_summary(results)
        with self.assertRaises(SystemExit):
            recorder.load_summary(path)

        results = self.passing_results()
        results[0]["status"] = "FAIL"
        path = self.write_summary(results)
        with self.assertRaises(SystemExit):
            recorder.load_summary(path)


if __name__ == "__main__":
    unittest.main()
