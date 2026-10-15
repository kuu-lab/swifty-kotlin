#!/usr/bin/env python3
"""Regressions preventing incomplete CI evidence from permitting SKIP removal."""

from __future__ import annotations

import copy
import unittest

import run_matrix
import summarize_evidence as summary


class EvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        document, _, _ = run_matrix.load_contract_sets(run_matrix.DEFAULT_CONTRACT_PAIRS)
        self.stages = [{"id": name, "status": "pass", "exitCode": 0}
                       for name in ("test_run_candidate", "test_run_matrix", "test_summarize_evidence")]
        self.evidence = {
            "status": "pass", "cases": [], "failureReasons": [],
            "gitRevision": run_matrix.git_text("rev-parse", "HEAD"), "compiler": {"sha256": "compiler-hash"},
            "compilerSourceTree": run_matrix.source_tree_identity(),
            "artifact": {"sha256": "artifact-hash", "manifestSha256": "manifest-hash",
                         "builderCompilerSha256": "compiler-hash", "builderSourceTreeSha256": run_matrix.source_tree_identity()["sha256"],
                         "builderGitRevision": run_matrix.git_text("rev-parse", "HEAD")},
            "expectationInputs": [{"path": path.relative_to(run_matrix.ROOT).as_posix(),
                                   "sha256": run_matrix.candidate.sha256_file(path)}
                                  for path, _ in run_matrix.DEFAULT_CONTRACT_PAIRS],
            "diagnosticMapInputs": [{"path": path.relative_to(run_matrix.ROOT).as_posix(),
                                    "sha256": run_matrix.candidate.sha256_file(path)}
                                   for _, path in run_matrix.DEFAULT_CONTRACT_PAIRS],
        }
        for case in document["cases"]:
            if "native-compat" in case.get("lanes", []):
                self.evidence["cases"].append({
                    "id": case["id"], "sourceSha256": case["sourceSha256"],
                    "matrix": {key: {"status": "pass", "compileExitCode": 0,
                                      "failureReasons": []} for key in summary.CELLS},
                })

    def test_complete_matrix_and_runner_regressions_are_required(self) -> None:
        report = summary.aggregate(self.evidence, self.stages)
        self.assertTrue(report["skipRemovalReady"])
        self.assertEqual(report["counts"]["pass"], 108)
        self.assertFalse(summary.aggregate(self.evidence, [])["skipRemovalReady"])

    def test_artifact_identity_is_required(self) -> None:
        self.evidence["artifact"]["builderCompilerSha256"] = "stale"
        self.assertFalse(summary.aggregate(self.evidence, self.stages)["skipRemovalReady"])

    def test_stdlib_timeout_leaves_fixture_cells_not_run(self) -> None:
        self.assertEqual(summary.classify({"failureReasons": ["stdlib_build_timeout"]}), "not-run")

    def test_partial_matrix_cannot_be_green(self) -> None:
        self.evidence["cases"].pop()
        report = summary.aggregate(self.evidence, self.stages)
        self.assertFalse(report["skipRemovalReady"])
        self.assertEqual(report["counts"]["not-run"], 4)

    def test_failure_timeout_and_not_run_are_distinct(self) -> None:
        cells = self.evidence["cases"][0]["matrix"]
        cells[summary.CELLS[0]] = {"status": "fail", "compileExitCode": 1,
                                  "failureReasons": ["compile_exit_mismatch"]}
        cells[summary.CELLS[1]] = {"status": "fail", "compileExitCode": None,
                                  "failureReasons": ["compile_timeout"]}
        cells[summary.CELLS[2]] = {"status": "fail", "compileExitCode": None,
                                  "failureReasons": ["stdlib_build_failed"]}
        cells[summary.CELLS[3]] = {"status": "fail", "compileExitCode": 1,
                                  "failureReasons": []}
        report = summary.aggregate(self.evidence, self.stages)
        self.assertEqual(report["counts"], {"pass": 104, "fail": 2, "timeout": 1, "not-run": 1})
        self.assertFalse(report["skipRemovalReady"])

    def test_stale_fixture_and_adapter_evidence_is_rejected(self) -> None:
        for field in ("sourceSha256",):
            evidence = copy.deepcopy(self.evidence)
            evidence["cases"][0][field] = "stale"
            self.assertFalse(summary.aggregate(evidence, self.stages)["skipRemovalReady"])
        for field in ("expectationInputs", "diagnosticMapInputs"):
            evidence = copy.deepcopy(self.evidence)
            evidence[field][0]["sha256"] = "stale"
            self.assertFalse(summary.aggregate(evidence, self.stages)["skipRemovalReady"])

    def test_fatal_matrix_failure_and_failed_regression_cannot_be_green(self) -> None:
        self.evidence["failureReasons"] = ["compiler_or_source_identity_changed_during_matrix"]
        self.assertFalse(summary.aggregate(self.evidence, self.stages)["skipRemovalReady"])
        self.evidence["failureReasons"] = []
        self.stages[0]["status"] = "timeout"
        self.assertFalse(summary.aggregate(self.evidence, self.stages)["skipRemovalReady"])

    def test_checked_in_failed_evidence_remains_failed(self) -> None:
        import json
        path = run_matrix.FIXTURE_ROOT / "evidence/native-matrix-results.json"
        report = summary.aggregate(json.loads(path.read_text()), self.stages)
        self.assertFalse(report["skipRemovalReady"])
        self.assertEqual(report["counts"]["fail"], 52)
        self.assertIn("SKIP removal ready: **false**", summary.render_markdown(report))


if __name__ == "__main__":
    unittest.main()
