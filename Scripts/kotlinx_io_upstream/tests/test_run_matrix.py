#!/usr/bin/env python3
"""Self-tests for result classification and artifact completeness."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
RUNNER = HERE.parent / "run_matrix.py"
FAKE = HERE / "fake_observer.py"
REPO_ROOT = HERE.parents[2]


def run_case(case_id: str, reference: str = "same", candidate: str = "same", **extra: object) -> dict[str, object]:
    case: dict[str, object] = {
        "id": case_id,
        "upstream_id": f"fixture::{case_id}",
        "upstream_path": "core/common/test/Fixture.kt",
        "test_kind": "test",
        "platform": "common",
        "mapping": "synthetic fixture only",
        "timeout_seconds": 0.15,
        "reference": {"command": [sys.executable, str(FAKE)], "env": {"KIO_FIXTURE": reference}},
        "candidate": {"command": [sys.executable, str(FAKE)], "env": {"KIO_FIXTURE": candidate}},
    }
    case.update(extra)
    return case


class MatrixRunnerTests(unittest.TestCase):
    def invoke(self, temp: Path, cases: list[dict[str, object]], run_id: str) -> tuple[subprocess.CompletedProcess[str], dict[str, object], Path]:
        manifest_path = temp / f"{run_id}.json"
        manifest_path.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "baseline": {"kotlin": "2.3.10", "kotlinx_io": "0.9.1"},
                    "cases": cases,
                }
            ),
            encoding="utf-8",
        )
        artifact_root = temp / "artifacts"
        completed = subprocess.run(
            [
                sys.executable,
                str(RUNNER),
                "--manifest",
                str(manifest_path),
                "--repo-root",
                str(REPO_ROOT),
                "--artifact-root",
                str(artifact_root),
                "--run-id",
                run_id,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        run_dir = artifact_root / run_id
        return completed, json.loads((run_dir / "summary.json").read_text(encoding="utf-8")), run_dir

    def test_classifies_comparison_failures_and_non_pass_dispositions(self) -> None:
        cases = [
            run_case("pass"),
            run_case("difference", candidate="different"),
            run_case("state-difference", candidate="state-different"),
            run_case("crash", reference="crash"),
            run_case("hang", reference="hang"),
            run_case("protocol-error", reference="invalid"),
            run_case("xfail", candidate="different", expected_failure="DIFFERENCE"),
            run_case("xpass", expected_failure="DIFFERENCE"),
            {"id": "skip", "platform": "jvm", "disposition": "skip", "reason": "fixture skip"},
            {"id": "unsupported", "platform": "native-macos", "disposition": "unsupported", "reason": "fixture platform gap"},
            {"id": "unmapped", "platform": "common", "disposition": "unmapped", "reason": "fixture mapping gap"},
            run_case("../escaped-case"),
        ]
        with tempfile.TemporaryDirectory(prefix="kio-matrix-test-") as tmp:
            completed, summary, run_dir = self.invoke(Path(tmp), cases, "classification")
            self.assertEqual(completed.returncode, 1, completed.stderr)
            self.assertEqual(summary["counts"]["total"], 12)
            self.assertEqual(summary["counts"]["passed"], 2)
            self.assertEqual(summary["counts"]["difference"], 2)
            self.assertEqual(summary["counts"]["crash"], 1)
            self.assertEqual(summary["counts"]["hang"], 1)
            self.assertEqual(summary["counts"]["error"], 1)
            self.assertEqual(summary["counts"]["xfail"], 1)
            self.assertEqual(summary["counts"]["xpass"], 1)
            self.assertEqual(summary["counts"]["skip"], 1)
            self.assertEqual(summary["counts"]["unsupported"], 1)
            self.assertEqual(summary["counts"]["unmapped"], 1)
            self.assertFalse(summary["complete"])
            self.assertTrue((run_dir / "summary.md").is_file())
            self.assertTrue((run_dir / "cases/pass/reference/stdout.txt").is_file())
            self.assertTrue((run_dir / "cases/difference/candidate/stderr.txt").is_file())
            escaped = next(case for case in summary["cases"] if case["id"] == "../escaped-case")
            escaped_result = run_dir / escaped["artifact_dir"] / "result.json"
            self.assertTrue(escaped_result.is_file())
            self.assertEqual(escaped_result.parent.parent.parent, run_dir)

    def test_exit_is_zero_only_for_all_pass(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kio-matrix-test-") as tmp:
            completed, summary, _ = self.invoke(Path(tmp), [run_case("only-pass")], "all-pass")
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(summary["complete"])
            self.assertEqual(summary["counts"]["passed"], 1)
            incomplete, incomplete_summary, _ = self.invoke(
                Path(tmp),
                [{"id": "only-skip", "platform": "common", "disposition": "skip", "reason": "no oracle"}],
                "only-skip",
            )
            self.assertEqual(incomplete.returncode, 2, incomplete.stderr)
            self.assertFalse(incomplete_summary["complete"])

    def test_accepts_exact_non_common_source_set_labels(self) -> None:
        cases = [
            {"id": "js-case", "platform": "js", "disposition": "unsupported", "reason": "fixture target"},
            {"id": "native-nonapple-case", "platform": "native-nonapple", "disposition": "unsupported", "reason": "fixture target"},
        ]
        with tempfile.TemporaryDirectory(prefix="kio-matrix-test-") as tmp:
            completed, summary, _ = self.invoke(Path(tmp), cases, "source-set-labels")
            self.assertEqual(completed.returncode, 2, completed.stderr)
            self.assertEqual(summary["counts"]["unsupported"], 2)
            self.assertEqual([case["platform"] for case in summary["cases"]], ["js", "native-nonapple"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
