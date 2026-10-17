#!/usr/bin/env python3
"""Failure-injection tests for the strict kotlinx-io CI gate."""

from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "verify_gate.py"
SPEC = importlib.util.spec_from_file_location("verify_gate", SCRIPT)
verify_gate = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(verify_gate)
FIXTURE = Path(__file__).parent / "fixtures/verified-coverage-map.complete.json"


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def minimal_root(root: Path) -> None:
    verified_map = json.loads(FIXTURE.read_text(encoding="utf-8"))
    case_id = "core/common/test/One.kt#read"
    source_path = "core/common/test/One.kt"
    source_sha256 = verified_map["mappings"][0]["source_sha256"]
    source_git_blob_sha = verified_map["mappings"][0]["source_git_blob_sha"]
    inventory = root / "Scripts/io_api_inventory/api-inventory.tsv"
    inventory.parent.mkdir(parents=True)
    inventory.write_text(
        "row_id\tmodule\trepresentation\tplatform_scope\tapi_kind\tname\tsignature\tstatus\t"
        "owner_issue\tupstream_test_refs\tlocal_test_refs\tlocal_implementation_refs\tlocal_contract_differences\n"
        "api-1\tcore\tKotlin source API / KLIB dump\tcommon\tfunction\tread\t()\tverified\t"
        "KUU-1\ttest.kt#read\tTests/read.swift\tSources/read.kt\tnone\n",
        encoding="utf-8",
    )
    write_json(root / "Scripts/io_api_inventory/upstream-tests-index.json", {
        "commit": "abc123", "files": [{"path": source_path, "testNames": ["read"]}],
    })
    write_json(root / "Scripts/io_api_inventory/upstream-lock.json", {"commit": "abc123"})
    write_json(root / "Scripts/kotlinx_io_upstream/coverage-map.seed.json", {
        "catalog": {"commit": "abc123"},
        "cases": [{"id": case_id, "upstream_id": case_id, "upstream_path": source_path,
                   "platform": "common", "disposition": "unmapped", "mapping": {
                       "status": "unmapped", "verified_assertion_mapping": False,
                   }, "upstream_metadata": {"git_blob_sha": source_git_blob_sha}}],
    })
    jvm_catalog = []
    native_catalog = []
    for mapping in verified_map["mappings"]:
        for execution in mapping["executions"]:
            row = {
                "execution_id": execution["execution_id"],
                "upstream_id": case_id,
                "upstream_path": source_path,
                "git_blob_sha": source_git_blob_sha,
                "source_set": "common",
                **execution["invocation"],
            }
            (jvm_catalog if execution["platform"] == "jvm" else native_catalog).append(row)
    jvm_path = root / "Scripts/kotlinx_io_upstream/jvm-executions.expected.json"
    native_path = root / "Scripts/kotlinx_io_upstream/native-executions.expected.json"
    write_json(jvm_path, jvm_catalog)
    write_json(native_path, native_catalog)
    write_json(root / "Scripts/kotlinx_io_upstream/reference-lock.json", {
        "commit": "abc123",
        "upstream_files": [{
            "path": source_path, "sha256": source_sha256, "git_blob_sha": source_git_blob_sha,
        }],
        "jvm_execution_catalog_sha256": hashlib.sha256(jvm_path.read_bytes()).hexdigest(),
        "native_execution_catalog_sha256": hashlib.sha256(native_path.read_bytes()).hexdigest(),
    })
    write_json(root / "Scripts/kotlinx_io_upstream/coverage-map.verified.json", verified_map)


def jvm_only_fixture(root: Path, include_native_candidate: bool) -> None:
    minimal_root(root)
    base = root / "Scripts/kotlinx_io_upstream"
    seed_path = base / "coverage-map.seed.json"
    seed = verify_gate.read_json(seed_path)
    seed["cases"][0]["platform"] = "jvm"
    write_json(seed_path, seed)

    verified_path = base / "coverage-map.verified.json"
    verified = verify_gate.read_json(verified_path)
    entry = verified["mappings"][0]
    entry["executions"] = [row for row in entry["executions"] if row["platform"] == "jvm"]
    if include_native_candidate:
        for row in entry["executions"]:
            row["candidate_platform"] = "native"
            row["candidate_execution_id"] = "native-bridge:" + row["execution_id"]
            row["candidate"]["target_platform"] = "native"
            row["candidate"]["execution_id"] = row["candidate_execution_id"]
    write_json(verified_path, verified)

    native_path = base / "native-executions.expected.json"
    write_json(native_path, [])
    lock_path = base / "reference-lock.json"
    lock = verify_gate.read_json(lock_path)
    lock["native_execution_catalog_sha256"] = hashlib.sha256(native_path.read_bytes()).hexdigest()
    write_json(lock_path, lock)


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
            self.assertEqual(report["upstream_tests"]["jvm_concrete_execution_count"], 2)
            self.assertEqual(report["upstream_tests"]["native_concrete_execution_count"], 2)
            self.assertEqual(report["upstream_tests"]["verified_source_function_count"], 1)
            self.assertEqual(report["upstream_tests"]["missing_source_function_count"], 0)
            self.assertEqual(len(mapping["api_rows"]), 1)
            self.assertEqual(len(mapping["execution_coverage"]), 1)
            execution_coverage = mapping["execution_coverage"][0]
            self.assertEqual(execution_coverage["disposition"], "paired")
            self.assertEqual(len(execution_coverage["jvm_execution_ids"]), 2)
            self.assertEqual(len(execution_coverage["native_execution_ids"]), 2)
            self.assertEqual(len(execution_coverage["verified_execution_mappings"]), 4)
            self.assertEqual(
                execution_coverage["verified_execution_mappings"][0]["candidate"]["observations"]["bytes_consumed"],
                2,
            )

    def test_jvm_only_function_requires_an_explicit_native_candidate_id(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            jvm_only_fixture(root, include_native_candidate=False)
            base = root / "Scripts/kotlinx_io_upstream"
            seed = verify_gate.read_json(base / "coverage-map.seed.json")
            index = verify_gate.read_json(root / "Scripts/io_api_inventory/upstream-tests-index.json")
            lock = verify_gate.read_json(base / "reference-lock.json")
            verified = verify_gate.read_json(base / "coverage-map.verified.json")
            jvm = verify_gate.read_json(base / "jvm-executions.expected.json")
            cases, blockers, summary = verify_gate.compose_verified_coverage(
                seed["cases"], index, lock, verified, jvm, [])
            self.assertFalse(summary["verified_source_function_count"])
            self.assertTrue(any(
                "must explicitly map the JVM-only reference to a Native candidate" in row["reason"]
                for row in blockers
            ))
            self.assertEqual(cases[0]["disposition"], "unmapped")

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            jvm_only_fixture(root, include_native_candidate=True)
            base = root / "Scripts/kotlinx_io_upstream"
            seed = verify_gate.read_json(base / "coverage-map.seed.json")
            index = verify_gate.read_json(root / "Scripts/io_api_inventory/upstream-tests-index.json")
            lock = verify_gate.read_json(base / "reference-lock.json")
            verified = verify_gate.read_json(base / "coverage-map.verified.json")
            jvm = verify_gate.read_json(base / "jvm-executions.expected.json")
            cases, blockers, summary = verify_gate.compose_verified_coverage(
                seed["cases"], index, lock, verified, jvm, [])
            self.assertFalse(blockers)
            self.assertEqual(summary["verified_source_function_count"], 1)
            self.assertEqual(cases[0]["mapping"]["verified_evidence"]["executions"][0]["candidate_platform"], "native")

    def test_static_audit_fails_missing_unverified_and_unmapped_rows(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            minimal_root(root)
            inventory = root / "Scripts/io_api_inventory/api-inventory.tsv"
            inventory.write_text(inventory.read_text().replace("\tverified\t", "\tunverified\t"),
                                 encoding="utf-8")
            verified_path = root / "Scripts/kotlinx_io_upstream/coverage-map.verified.json"
            verified = verify_gate.read_json(verified_path)
            verified["mappings"] = []
            write_json(verified_path, verified)
            report, _ = verify_gate.audit_static(root)
            self.assertEqual(report["status"], "FAIL")
            self.assertTrue(any(row["kind"] == "api-status" and row["reason"] == "unverified"
                                for row in report["blockers"]))
            self.assertTrue(any(row["kind"] == "test-mapping" and row["reason"] == "unmapped"
                                for row in report["blockers"]))

    def test_seed_disposition_cannot_promote_a_function_without_verified_mapping(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            minimal_root(root)
            seed_path = root / "Scripts/kotlinx_io_upstream/coverage-map.seed.json"
            seed = verify_gate.read_json(seed_path)
            seed["cases"][0]["disposition"] = "paired"
            seed["cases"][0]["mapping"] = {"status": "verified", "verified_assertion_mapping": True}
            write_json(seed_path, seed)
            verified_path = root / "Scripts/kotlinx_io_upstream/coverage-map.verified.json"
            verified = verify_gate.read_json(verified_path)
            verified["mappings"] = []
            write_json(verified_path, verified)

            report, mapping = verify_gate.audit_static(root)
            self.assertEqual(report["status"], "FAIL")
            self.assertEqual(mapping["execution_coverage"][0]["disposition"], "unmapped")

    def test_verified_mapping_rejects_missing_parameter_and_does_not_promote_partial_function(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            minimal_root(root)
            verified_path = root / "Scripts/kotlinx_io_upstream/coverage-map.verified.json"
            verified = verify_gate.read_json(verified_path)
            verified["mappings"][0]["executions"].pop(1)
            write_json(verified_path, verified)

            report, mapping = verify_gate.audit_static(root)
            self.assertEqual(report["status"], "FAIL")
            self.assertEqual(report["upstream_tests"]["missing_source_function_count"], 1)
            self.assertTrue(any(
                row["id"] == "core/common/test/One.kt#read"
                and "missing concrete execution mapping jvm:"
                in row["reason"]
                for row in report["blockers"]
            ))
            self.assertEqual(mapping["execution_coverage"][0]["disposition"], "unmapped")
            self.assertEqual(mapping["execution_coverage"][0]["verified_execution_mappings"], [])

    def test_verified_mapping_rejects_duplicate_unknown_stale_and_unfinished_evidence(self):
        mutations = {
            "duplicate upstream ID": lambda data: data["mappings"].append(copy.deepcopy(data["mappings"][0])),
            "unknown upstream ID": lambda data: data["mappings"].append({**copy.deepcopy(data["mappings"][0]), "upstream_id": "missing.kt#unknown"}),
            "source hash mismatch": lambda data: data["mappings"][0].update({"source_sha256": "0" * 64}),
            "commit mismatch": lambda data: data.update({"upstream_commit": "different-commit"}),
            "skipped parameter": lambda data: data["mappings"][0]["executions"][1]["candidate"]["result"].update({"status": "SKIP"}),
            "expected failure": lambda data: data["mappings"][0]["executions"][1]["reference"]["result"].update({"status": "EXPECTED_FAILURE"}),
            "missing byte observation": lambda data: data["mappings"][0]["executions"][1]["candidate"]["observations"].pop("bytes_consumed"),
        }
        for label, mutate in mutations.items():
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                minimal_root(root)
                verified_path = root / "Scripts/kotlinx_io_upstream/coverage-map.verified.json"
                verified = verify_gate.read_json(verified_path)
                mutate(verified)
                write_json(verified_path, verified)
                report, mapping = verify_gate.audit_static(root)
                self.assertEqual(report["status"], "FAIL")
                if label != "unknown upstream ID":
                    self.assertEqual(mapping["execution_coverage"][0]["disposition"], "unmapped")
                self.assertTrue(report["blockers"], label)

    def test_seed_regeneration_keeps_verified_mapping_file_separate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            seed_path = root / "coverage-map.seed.json"
            verified_path = root / "coverage-map.verified.json"
            index_path = root / "upstream-tests-index.json"
            verified = json.loads(FIXTURE.read_text(encoding="utf-8"))
            write_json(verified_path, verified)
            original_verified_bytes = verified_path.read_bytes()
            write_json(index_path, {
                "tag": "0.9.1",
                "commit": "362bdc35e159bad6da1e08101c8321792d762281",
                "files": [{"path": "core/common/test/One.kt", "testNames": ["read"]}],
            })
            result = subprocess.run(
                [sys.executable, str(SCRIPT.parent / "import_inventory.py"),
                 "--test-index", str(index_path), "--output", str(seed_path)],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(verified_path.read_bytes(), original_verified_bytes)
            regenerated = verify_gate.read_json(seed_path)
            self.assertEqual(regenerated["cases"][0]["disposition"], "unmapped")

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
