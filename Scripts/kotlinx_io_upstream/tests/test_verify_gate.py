#!/usr/bin/env python3
"""Failure-injection tests for the strict kotlinx-io CI gate."""

from __future__ import annotations

import importlib.util
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "verify_gate.py"
SPEC = importlib.util.spec_from_file_location("verify_gate", SCRIPT)
verify_gate = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(verify_gate)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def minimal_root(root: Path) -> None:
    inventory = root / "Scripts/io_api_inventory/api-inventory.tsv"
    inventory.parent.mkdir(parents=True)
    inventory.write_text(
        "row_id\tmodule\trepresentation\tplatform_scope\tapi_kind\tname\tsignature\tstatus\t"
        "owner_issue\tupstream_test_refs\tlocal_test_refs\tlocal_implementation_refs\tlocal_contract_differences\n"
        "api-1\tcore\tKotlin source API / KLIB dump\tcommon\tfunction\tread\t()\tverified\t"
        "KUU-1\ttest.kt#read\tTests/read.swift\tSources/read.kt\tnone\n",
        encoding="utf-8",
    )
    test_id = "core/common/test/One.kt#read"
    write_json(root / "Scripts/io_api_inventory/upstream-tests-index.json", {
        "commit": "abc123", "files": [{"path": "core/common/test/One.kt", "testNames": ["read"]}],
    })
    write_json(root / "Scripts/io_api_inventory/upstream-lock.json", {"commit": "abc123"})
    write_json(root / "Scripts/kotlinx_io_upstream/coverage-map.seed.json", {
        "catalog": {"commit": "abc123"},
        "cases": [{"id": test_id, "upstream_id": test_id, "upstream_path": "core/common/test/One.kt",
                   "platform": "common", "disposition": "paired", "mapping": {
                       "status": "verified", "verified_assertion_mapping": True,
                   }}],
    })
    jvm_catalog = [
        {"execution_id": "jvm.One.read", "upstream_id": test_id},
    ]
    native_catalog = [
        {"execution_id": "native.One.read", "upstream_id": test_id},
    ]
    jvm_path = root / "Scripts/kotlinx_io_upstream/jvm-executions.expected.json"
    native_path = root / "Scripts/kotlinx_io_upstream/native-executions.expected.json"
    write_json(jvm_path, jvm_catalog)
    write_json(native_path, native_catalog)
    write_json(root / "Scripts/kotlinx_io_upstream/reference-lock.json", {
        "commit": "abc123",
        "jvm_execution_catalog_sha256": hashlib.sha256(jvm_path.read_bytes()).hexdigest(),
        "native_execution_catalog_sha256": hashlib.sha256(native_path.read_bytes()).hexdigest(),
    })
    write_json(root / "Scripts/kotlinx_io_upstream/native-executions.expected.json", [
        {"execution_id": "native.One.read", "upstream_id": test_id},
    ])


def complete_f02_summary() -> dict:
    lanes = [list(lane) for lane in sorted(verify_gate.F02_LANES)]
    cases = ["case-a", "case-b"]
    results = [
        {"case": case, "route": route, "optimization": optimization, "status": "PASS"}
        for case in cases for route, optimization in verify_gate.F02_LANES
    ]
    return {"status": "SELECTED_MATRIX_PASS", "selected_cases": cases,
            "expected_case_ids": list(cases), "lanes": lanes, "results": results}


def complete_diff_summary(optimization: str = "O0") -> dict:
    case_statuses = {"one.kt": "PASS", "two.kt": "PASS"}
    return {
        "kind": "kotlinx-io-diff-matrix", "status": "PASS",
        "expected_case_count": 2, "required_optimization": optimization,
        "case_manifest": [{"name": name, "sha256": "abc"} for name in case_statuses],
        "optimizations": {optimization: {
            "status": "PASS", "exit_code": 0, "timed_out": False,
            "counts": {"PASS": 2}, "case_statuses": case_statuses,
        }},
    }


class VerifyGateTests(unittest.TestCase):
    def test_only_exact_all_pass_counts_are_accepted(self):
        self.assertEqual(verify_gate.validate_execution_counts({"PASS": 3}, 3, "sample"), [])
        for state in ("FAIL", "TIMEOUT", "CRASH", "SKIP", "EXPECTED_FAILURE", "MISSING", "NOT_RUN"):
            with self.subTest(state=state):
                problems = verify_gate.validate_execution_counts({"PASS": 2, state: 1}, 3, "sample")
                self.assertTrue(problems)
                self.assertTrue(any(state in problem for problem in problems))

    def test_zero_execution_cannot_pass(self):
        problems = verify_gate.validate_execution_counts({}, 3, "sample")
        self.assertTrue(any("result count 0" in problem for problem in problems))
        self.assertTrue(any("PASS=0" in problem for problem in problems))

    def test_upstream_case_inventory_is_derived_from_test_names(self):
        index = {"files": [{"path": "core/common/test/One.kt", "testNames": ["first", "second"]}]}
        self.assertEqual(verify_gate.inventory_case_ids(index), {
            "core/common/test/One.kt#first", "core/common/test/One.kt#second",
        })

    def test_static_audit_accepts_complete_mapping_and_counts_execution_catalogs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            minimal_root(root)
            report, mapping = verify_gate.audit_static(root)
            self.assertEqual(report["status"], "PASS")
            self.assertEqual(report["api"]["row_count"], 1)
            self.assertEqual(report["upstream_tests"]["coverage_case_count"], 1)
            self.assertEqual(report["upstream_tests"]["jvm_concrete_execution_count"], 1)
            self.assertEqual(len(mapping["api_rows"]), 1)
            self.assertEqual(len(mapping["execution_coverage"]), 1)
            self.assertEqual(mapping["execution_coverage"][0]["jvm_execution_ids"], ["jvm.One.read"])
            self.assertEqual(mapping["execution_coverage"][0]["native_execution_ids"], ["native.One.read"])

    def test_static_audit_fails_missing_unverified_and_unmapped_rows(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            minimal_root(root)
            inventory = root / "Scripts/io_api_inventory/api-inventory.tsv"
            inventory.write_text(inventory.read_text().replace("\tverified\t", "\tunverified\t"),
                                 encoding="utf-8")
            coverage_path = root / "Scripts/kotlinx_io_upstream/coverage-map.seed.json"
            coverage = verify_gate.read_json(coverage_path)
            coverage["cases"][0]["disposition"] = "unmapped"
            coverage["cases"][0]["mapping"] = {"status": "candidate-unverified"}
            write_json(coverage_path, coverage)
            report, _ = verify_gate.audit_static(root)
            self.assertEqual(report["status"], "FAIL")
            self.assertTrue(any(row["kind"] == "api-status" and row["reason"] == "unverified"
                                for row in report["blockers"]))
            self.assertTrue(any(row["kind"] == "test-mapping" and row["reason"] == "unmapped"
                                for row in report["blockers"]))

    def test_static_audit_rejects_each_incomplete_api_state(self):
        for status in ("missing", "stub", "unverified"):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                minimal_root(root)
                inventory = root / "Scripts/io_api_inventory/api-inventory.tsv"
                inventory.write_text(inventory.read_text().replace("\tverified\t", f"\t{status}\t"),
                                     encoding="utf-8")
                report, _ = verify_gate.audit_static(root)
                self.assertTrue(any(row["kind"] == "api-status" and row["reason"] == status
                                    for row in report["blockers"]))

    def test_static_audit_detects_a_test_added_to_the_upstream_index(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            minimal_root(root)
            index_path = root / "Scripts/io_api_inventory/upstream-tests-index.json"
            index = verify_gate.read_json(index_path)
            index["files"][0]["testNames"].append("newUpstreamTest")
            write_json(index_path, index)
            report, _ = verify_gate.audit_static(root)
            self.assertTrue(any(
                row["kind"] == "test-coverage"
                and row["id"] == "core/common/test/One.kt#newUpstreamTest"
                and row["reason"] == "missing from coverage map"
                for row in report["blockers"]
            ))

    def test_summaries_with_skips_and_expected_failures_are_rejected(self):
        for state in ("SKIP", "EXPECTED_FAILURE", "TIMEOUT", "CRASH"):
            with self.subTest(state=state):
                result = {"status": "FAIL", "expected_count": 2, "counts": {"PASS": 1, state: 1}}
                problems = verify_gate.validate_summary(result, "candidate-summary.json")
                self.assertTrue(problems)

    def test_f02_requires_each_selected_case_in_all_six_lanes_exactly_once(self):
        self.assertEqual(verify_gate.validate_summary(complete_f02_summary(), "f02-summary.json"), [])
        self.assertTrue(verify_gate.validate_summary(
            {"status": "SELECTED_MATRIX_PASS", "results": []},
            "artifact/f02/results/summary.json",
        ))
        incomplete = complete_f02_summary()
        incomplete["results"].pop()
        incomplete["results"].append(dict(incomplete["results"][0]))
        problems = verify_gate.validate_summary(incomplete, "f02-summary.json")
        self.assertTrue(any("missing, duplicate, or unexpected" in problem for problem in problems))

    def test_diff_gate_rejects_missing_lane_failure_or_timeout(self):
        self.assertEqual(verify_gate.validate_summary(complete_diff_summary("O0"), "diff-O0.json"), [])
        for update in (
            {"optimizations": {"O1": complete_diff_summary()["optimizations"]["O0"]}},
            {"optimizations": {"O0": {**complete_diff_summary()["optimizations"]["O0"], "timed_out": True}}},
            {"optimizations": {"O0": {**complete_diff_summary()["optimizations"]["O0"], "exit_code": 1}}},
        ):
            with self.subTest(update=update):
                summary = complete_diff_summary("O0")
                summary.update(update)
                self.assertTrue(verify_gate.validate_summary(summary, "diff-O0.json"))

    def test_ktor_summary_requires_one_pass_for_each_optimization(self):
        summary = {"kind": "ktor-io-consumer", "status": "PASS", "exit_code": 0,
                   "expected_lane_count": 2,
                   "optimization_lanes": [
                       "PASS ktor_io_macos compile + consumer link/run O0",
                       "PASS ktor_io_macos compile + consumer link/run O2",
                   ]}
        self.assertEqual(verify_gate.validate_summary(summary, "ktor-summary.json"), [])
        summary["optimization_lanes"] = [
            "PASS ktor_io_macos compile + consumer link/run O0",
            "PASS ktor_io_macos compile + consumer link/run O0",
        ]
        self.assertTrue(verify_gate.validate_summary(summary, "ktor-summary.json"))

    def test_candidate_matrix_cannot_pass_with_a_partial_native_catalog(self):
        summary = {
            "status": "PASS", "optimization": "O2", "stdlib_mode": "library",
            "test_body_mode": "source", "expected_count": 3, "counts": {"PASS": 3},
        }
        problems = verify_gate.validate_summary(
            summary, "artifact/candidate/stdlib-library-O2/summary.json",
            expected_native_execution_count=4,
        )
        self.assertTrue(any("full Native catalog" in problem for problem in problems))

    def test_candidate_matrix_rejects_a_selected_manifest_with_missing_execution_ids(self):
        selection = {
            "selection_mode": "explicit-ids", "target_catalog_execution_count": 4,
            "selected_execution_count": 3, "requested_source_function_ids": ["source#one"],
            "requested_execution_ids": [],
            "selected_execution_ids": ["native.one", "native.two", "native.three"],
            "input_hashes": {
                "workspace_git_sha": "abc123", "compiler_sha256": "a" * 64,
                "runtime_sources_sha256": "b" * 64, "catalog_sha256": "c" * 64,
                "runner_sha256": "d" * 64, "driver_sha256": "e" * 64,
            },
        }
        summary = {
            "status": "PASS", "optimization": "O2", "stdlib_mode": "library",
            "test_body_mode": "source", "workspace_git_sha": "abc123",
            "expected_count": 3, "counts": {"PASS": 3}, "selection": selection,
            "selection_manifest_sha256": "f" * 64,
        }
        problems = verify_gate.validate_summary(
            summary, "artifact/candidate/stdlib-library-O2/summary.json", "abc123", 4,
            expected_native_execution_ids={"native.one", "native.two", "native.three", "native.four"},
        )
        self.assertTrue(any("selection mode" in problem for problem in problems))
        self.assertTrue(any("candidate execution count" in problem for problem in problems))
        self.assertTrue(any("selected execution IDs do not cover" in problem for problem in problems))

    def test_candidate_artifacts_reject_partial_results_and_a_different_locked_catalog(self):
        with tempfile.TemporaryDirectory() as temporary:
            summary_path = Path(temporary) / "summary.json"
            selected_ids = ["native.One.read", "native.Two.read"]
            selection = {
                "schema_version": 1, "selection_mode": "full-target-catalog", "target": "macos",
                "upstream_commit": "pinned", "catalog_sha256": "a" * 64,
                "catalog_execution_count": 2, "target_catalog_execution_count": 2,
                "covers_full_catalog": True, "selected_execution_count": 2,
                "requested_source_function_ids": [], "requested_execution_ids": [],
                "selected_execution_ids": selected_ids,
                "selected_source_function_ids": ["core/common/test/One.kt#read"],
                "input_hashes": {
                    "workspace_git_sha": "pinned", "compiler_sha256": "a" * 64,
                    "runtime_sources_sha256": "b" * 64, "catalog_sha256": "b" * 64,
                    "runner_sha256": "d" * 64, "driver_sha256": "e" * 64,
                },
            }
            manifest_path = summary_path.with_name("selection.json")
            write_json(manifest_path, selection)
            write_json(summary_path.with_name("results.json"), [
                {"execution_id": selected_ids[0], "status": "PASS"},
            ])
            summary = {
                "selection": selection,
                "selection_manifest_sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
                "inputs": {**selection["input_hashes"],
                           "selection_manifest_sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest()},
            }
            problems = verify_gate.validate_candidate_artifacts(
                summary, summary_path, "candidate/source-O0/summary.json",
                set(selected_ids), {"core/common/test/One.kt#read"}, "c" * 64, "pinned",
            )
            self.assertTrue(any("candidate Native catalog hash" in problem for problem in problems))
            self.assertTrue(any("candidate input Native catalog hash" in problem for problem in problems))
            self.assertTrue(any("result IDs differ" in problem for problem in problems))

    def test_finalizer_rejects_receipts_from_another_workflow_attempt(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            evidence = root / "evidence"
            write_json(evidence / "job-receipt.json", {
                "job": "api-audit", "status": "success", "commit": "abc123",
                "run_id": "42", "run_attempt": "1",
            })
            args = type("Args", (), {
                "evidence": evidence,
                "job_results_json": json.dumps({"api-audit": {"result": "success"}}),
                "expected_receipts": ["api-audit"], "commit": "abc123",
                "run_id": "43", "run_attempt": "1", "output": root / "out",
            })()
            self.assertEqual(verify_gate.finalize_command(args), 1)
            result = verify_gate.read_json(root / "out/gate-summary.json")
            self.assertTrue(any("belongs to run" in problem for problem in result["blockers"]))

    def test_finalizer_accepts_a_complete_same_run_evidence_set(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            evidence = root / "evidence"
            expected_receipts = [
                "api-audit", "reference-jvm", "reference-native-apple", "f02-matrix",
                "candidate-source-O0", "candidate-source-O2",
                "candidate-stdlib-library-O0", "candidate-stdlib-library-O2",
                "candidate-producer-consumer-O0", "candidate-producer-consumer-O2",
                "ktor-consumer", "diff-O0", "diff-O2", "related-goldens",
            ]
            for name in expected_receipts:
                write_json(evidence / f"receipts/{name}/job-receipt.json", {
                    "job": name, "status": "success", "commit": "abc123",
                    "run_id": "42", "run_attempt": "1",
                })

            api_artifact = evidence / "kotlinx-io-gate-api-42-1"
            write_json(api_artifact / "api-gate-summary.json", {
                "status": "PASS", "commit": "abc123", "upstream_commit": "abc123",
                "api": {"row_count": 1},
                "upstream_tests": {
                    "coverage_case_count": 1,
                    "jvm_concrete_execution_count": 1,
                    "native_concrete_execution_count": 1,
                    "native_source_function_count": 1,
                    "native_execution_catalog_sha256": "c" * 64,
                },
            })
            write_json(api_artifact / "api-coverage-mapping.json", {
                "upstream_commit": "abc123",
                "execution_catalog_sha256": {"native": "c" * 64},
                "api_rows": [{}],
                "upstream_test_cases": [{"upstream_id": "core/common/test/One.kt#read"}],
                "execution_coverage": [{
                    "upstream_id": "core/common/test/One.kt#read", "disposition": "paired",
                    "jvm_execution_ids": ["jvm.One.read"], "native_execution_ids": ["native.One.read"],
                }],
            })

            for kind in ("jvm", "native-apple"):
                write_json(evidence / f"kotlinx-io-gate-reference-{kind}-42-1/reference/results/summary.json", {
                    "kind": "reference-only", "concrete_execution_count": 1,
                    "reference_counts": {"PASS": 1},
                })

            f02 = complete_f02_summary()
            f02["workspace_git_sha"] = "abc123"
            write_json(evidence / "kotlinx-io-gate-f02-42-1/f02/results/summary.json", f02)

            for route in ("source", "stdlib-library", "producer-consumer"):
                for optimization in ("O0", "O2"):
                    lane = f"{route}-{optimization}"
                    summary_path = evidence / f"kotlinx-io-gate-candidate-{lane}-42-1/candidate/{lane}/summary.json"
                    selection = {
                        "schema_version": 1, "selection_mode": "full-target-catalog", "target": "macos",
                        "upstream_commit": "abc123", "catalog_sha256": "c" * 64,
                        "catalog_execution_count": 1, "target_catalog_execution_count": 1,
                        "covers_full_catalog": True, "selected_execution_count": 1,
                        "requested_source_function_ids": [], "requested_execution_ids": [],
                        "selected_execution_ids": ["native.One.read"],
                        "selected_source_function_ids": ["core/common/test/One.kt#read"],
                        "input_hashes": {
                            "workspace_git_sha": "abc123", "compiler_sha256": "a" * 64,
                            "runtime_sources_sha256": "b" * 64, "catalog_sha256": "c" * 64,
                            "runner_sha256": "d" * 64, "driver_sha256": "e" * 64,
                        },
                    }
                    manifest_path = summary_path.with_name("selection.json")
                    write_json(manifest_path, selection)
                    write_json(summary_path.with_name("results.json"), [
                        {"execution_id": "native.One.read", "status": "PASS"},
                    ])
                    write_json(summary_path, {
                        "status": "PASS", "workspace_git_sha": "abc123", "optimization": optimization,
                        "stdlib_mode": "source" if route == "source" else "library",
                        "test_body_mode": "library-consumer" if route == "producer-consumer" else "source",
                        "expected_count": 1, "counts": {"PASS": 1}, "selection": selection,
                        "inputs": {**selection["input_hashes"],
                                   "selection_manifest_sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest()},
                        "selection_manifest_sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
                    })

            write_json(evidence / "kotlinx-io-gate-ktor-42-1/ktor/summary.json", {
                "kind": "ktor-io-consumer", "status": "PASS", "exit_code": 0,
                "expected_lane_count": 2,
                "optimization_lanes": [
                    "PASS ktor_io_macos compile + consumer link/run O0",
                    "PASS ktor_io_macos compile + consumer link/run O2",
                ],
            })
            for optimization in ("O0", "O2"):
                diff = complete_diff_summary(optimization)
                diff["commit"] = "abc123"
                write_json(evidence / f"kotlinx-io-gate-diff-{optimization}-42-1/diff/{optimization}/summary.json", diff)
            write_json(evidence / "kotlinx-io-gate-goldens-42-1/goldens/summary.json", {
                "status": "PASS", "exit_code": 0,
            })

            jobs = {name: {"result": "success"} for name in (
                "api-audit", "upstream-reference", "f02-matrix", "candidate-native",
                "ktor-consumer", "kotlinx-diff", "related-goldens",
            )}
            args = type("Args", (), {
                "evidence": evidence, "job_results_json": json.dumps(jobs),
                "expected_receipts": expected_receipts, "commit": "abc123",
                "run_id": "42", "run_attempt": "1", "output": root / "out",
            })()
            self.assertEqual(verify_gate.finalize_command(args), 0)
            result = verify_gate.read_json(root / "out/gate-summary.json")
            self.assertEqual(result["status"], "PASS")
            reference_summaries = [row for row in result["summaries"] if "/reference/results/summary.json" in row["artifact_file"]]
            self.assertEqual([row["status"] for row in reference_summaries], ["PASS", "PASS"])


if __name__ == "__main__":
    unittest.main()
