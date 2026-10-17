#!/usr/bin/env python3
"""Exercise validation evidence application with a one-row inventory fixture."""

import copy
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


HERE = Path(__file__).resolve().parent


def load_generator():
    spec = importlib.util.spec_from_file_location("io_inventory_generator", HERE / "generate.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ValidationEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generator = load_generator()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="io-validation-evidence-")
        self.root = Path(self.temporary.name)
        self.repository = self.root / "checkout"
        self.upstream = self.repository / "Scripts/io_api_inventory/upstream/kotlinx-io-0.9.1"
        self.evidence_path = self.root / "evidence.json"
        self._write("Sources/CompilerCore/Stdlib/kotlinx/io/Foo.kt", "fun foo() = 1\n")
        self._write("Sources/Runtime/io_bridge.swift", "func kk_io_foo() {}\n")
        self._write("Tests/CompilerBackendTests/FooTests.swift", "func testFoo() {}\n")
        self._write("core/common/test/FooTest.kt", "fun testFoo() = assertEquals(1, foo())\n", self.upstream)
        self.row = {
            "row_id": "klib-fixture-foo",
            "representation": "Kotlin source API / KLIB dump",
            "local_candidate_refs": "Sources/CompilerCore/Stdlib/kotlinx/io/Foo.kt:1",
            "local_implementation_refs": (
                "Sources/CompilerCore/Stdlib/kotlinx/io/Foo.kt:1;Sources/Runtime/io_bridge.swift:1"
            ),
            "local_test_refs": "Tests/CompilerBackendTests/FooTests.swift",
            "upstream_test_refs": "core/common/test/FooTest.kt#testFoo",
            "status": "unverified",
            "_inventory_status": "unverified",
        }
        self.lock = {"tag": "0.9.1", "commit": self.generator.EXPECTED_TAG_COMMIT}

    def tearDown(self):
        self.temporary.cleanup()

    def _write(self, relative, content, root=None):
        path = (root or self.repository) / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def _record(self, row=None):
        row = row or self.row
        executions = []
        lanes = self.generator.required_execution_lanes(self.generator.validation_obligations(row))
        for index, lane in enumerate(lanes):
            executions.append({
                "case_id": "core/common/test/FooTest.kt#testFoo",
                "lane": lane,
                "reference": {
                    "execution_id": f"reference-{index}",
                    "result": "PASS",
                    "exit_code": 0,
                },
                "candidate": {
                    "execution_id": f"candidate-{index}",
                    "result": "PASS",
                    "exit_code": 0,
                },
            })
        return {
            "row_id": row["row_id"],
            "candidate_sha": "a" * 40,
            "reference_version": self.lock["tag"],
            "reference_commit": self.lock["commit"],
            **self.generator.validation_input_hashes(row, self.repository, self.upstream),
            "compatibility_obligations": self.generator.validation_obligations(row),
            "executions": executions,
        }

    def _execution_catalogs(self):
        case_id = "core/common/test/FooTest.kt#testFoo"
        other_case_id = "core/common/test/BarTest.kt#testBar"
        return {
            "reference": {f"reference-{index}": case_id for index in range(6)}
            | {"reference-wrong": other_case_id},
            "candidate": {f"candidate-{index}": case_id for index in range(6)}
            | {"candidate-wrong": other_case_id},
        }

    def _apply(self, records, row=None, probe_catalog=None, execution_catalogs=None):
        fixture_row = copy.deepcopy(row or self.row)
        self.evidence_path.write_text(json.dumps({"schema_version": 1, "records": records}), encoding="utf-8")
        self.generator.apply_validation_evidence(
            [fixture_row], self.lock, self.evidence_path, self.repository, self.upstream,
            execution_catalogs or self._execution_catalogs(), probe_catalog,
        )
        return fixture_row

    def _probe_evidence(self):
        case_id = "api-probe:fixture:foo-public-type"
        record = self._record()
        catalog = {
            self.row["row_id"]: {
                "case_id": case_id,
                "lanes": self.generator.required_execution_lanes(record["compatibility_obligations"]),
            }
        }
        execution_catalogs = {"reference": {}, "candidate": {}}
        for execution in record["executions"]:
            lane = execution["lane"]
            execution["case_id"] = case_id
            for subject in ("reference", "candidate"):
                execution_id = (f"{self.row['row_id']}:shared-reference" if subject == "reference"
                                else f"{self.row['row_id']}:{lane}:candidate")
                execution[subject]["execution_id"] = execution_id
                execution_catalogs[subject][execution_id] = {
                    "case_id": case_id,
                    "lane": "shared" if subject == "reference" else lane,
                    "candidate_sha": record["candidate_sha"],
                    "reference_version": record["reference_version"],
                    "reference_commit": record["reference_commit"],
                }
        return record, catalog, execution_catalogs

    def test_current_reference_and_candidate_passes_promote_only_the_fixture_row(self):
        row = self._apply([self._record()])
        self.assertEqual(row["status"], "verified")
        rendered = self.generator.render_tsv(
            HERE / "api-inventory.tsv", self.generator.LEDGER_COLUMNS, [row]
        )
        self.assertEqual(rendered.splitlines()[1].split("\t")[21], "verified")
        repeated = self._apply([self._record()])
        repeated_rendered = self.generator.render_tsv(
            HERE / "api-inventory.tsv", self.generator.LEDGER_COLUMNS, [repeated]
        )
        self.assertEqual(repeated_rendered, rendered)

    def test_status_text_without_evidence_does_not_promote(self):
        row = copy.deepcopy(self.row)
        row["status"] = "verified"
        self.assertEqual(self._apply([], row)["status"], "unverified")

    def test_input_changes_invalidate_recorded_evidence(self):
        for relative in (
            "Sources/CompilerCore/Stdlib/kotlinx/io/Foo.kt",
            "Tests/CompilerBackendTests/FooTests.swift",
        ):
            with self.subTest(relative=relative):
                record = self._record()
                path = self.repository / relative
                path.write_text(path.read_text(encoding="utf-8") + "// changed\n", encoding="utf-8")
                with self.assertRaises(SystemExit):
                    self._apply([record])
                path.write_text(path.read_text(encoding="utf-8").replace("// changed\n", ""), encoding="utf-8")

    def test_non_passing_or_nonzero_candidate_execution_is_rejected(self):
        for result, exit_code in (("FAIL", 0), ("PASS", 1), ("NOT_RUN", 0)):
            with self.subTest(result=result, exit_code=exit_code):
                record = self._record()
                record["executions"][0]["candidate"]["result"] = result
                record["executions"][0]["candidate"]["exit_code"] = exit_code
                with self.assertRaises(SystemExit):
                    self._apply([record])

    def test_native_bridge_optimization_lane_cannot_be_omitted(self):
        record = self._record()
        record["executions"] = record["executions"][:1]
        with self.assertRaisesRegex(SystemExit, "missing validation lanes.*producer-consumer-O2"):
            self._apply([record])

    def test_unrelated_case_and_false_positive_execution_mapping_are_rejected(self):
        unrelated_case = self._record()
        unrelated_case["executions"][0]["case_id"] = "core/common/test/BarTest.kt#testBar"
        wrong_execution = self._record()
        wrong_execution["executions"][0]["candidate"]["execution_id"] = "candidate-wrong"
        for record in (unrelated_case, wrong_execution):
            with self.subTest(record=record):
                with self.assertRaises(SystemExit):
                    self._apply([record])

    def test_suite_reference_does_not_authorize_any_case_in_the_file(self):
        row = copy.deepcopy(self.row)
        row["upstream_test_refs"] = "core/common/test/FooTest.kt#suite-reference"
        with self.assertRaisesRegex(SystemExit, "is not mapped to row"):
            self._apply([self._record(row)], row)

    def test_row_owned_probe_case_can_promote_only_after_every_lane_passes(self):
        record, probe_catalog, execution_catalogs = self._probe_evidence()
        promoted = self._apply([record], probe_catalog=probe_catalog, execution_catalogs=execution_catalogs)
        self.assertEqual(promoted["status"], "verified")

    def test_probe_case_cannot_be_reused_by_another_row(self):
        record, probe_catalog, execution_catalogs = self._probe_evidence()
        probe_catalog["klib-fixture-other"] = probe_catalog.pop(self.row["row_id"])
        with self.assertRaisesRegex(SystemExit, "not mapped to row"):
            self._apply([record], probe_catalog=probe_catalog, execution_catalogs=execution_catalogs)

    def test_probe_execution_must_match_its_recorded_lane(self):
        record, probe_catalog, execution_catalogs = self._probe_evidence()
        first = record["executions"][0]
        execution_catalogs["candidate"][first["candidate"]["execution_id"]]["lane"] = "source-O2"
        with self.assertRaisesRegex(SystemExit, "wrong lane"):
            self._apply([record], probe_catalog=probe_catalog, execution_catalogs=execution_catalogs)

    def test_probe_receipt_checks_complete_passes_and_output_hashes(self):
        case_id = "api-probe:fixture:receipt"
        row_id = "klib-fixture-foo"
        lane = "source-O0"
        def result(subject):
            output = f"{subject}:pass\n"
            return {
                "execution_id": f"{row_id}:{lane}:{subject}",
                "result": "PASS",
                "exit_code": 0,
                "command": [subject, lane],
                "stdout": output,
                "stderr": "",
                "stdout_sha256": hashlib.sha256(output.encode()).hexdigest(),
                "stderr_sha256": hashlib.sha256(b"").hexdigest(),
            }
        payload = {
            "schema_version": 1,
            "candidate_sha": "a" * 40,
            "candidate_compiler_sha256": "b" * 64,
            "reference_version": "0.9.1",
            "reference_kotlin_version": "2.3.10",
            "reference_commit": self.generator.EXPECTED_TAG_COMMIT,
            "probe_inputs_sha256": {"reference:test-input": "c" * 64},
            "summary": {"case_count": 1, "lane_count": 1, "passed": 1, "failed": 0},
            "executions": [{"row_id": row_id, "case_id": case_id, "lane": lane,
                            "reference": result("reference"), "candidate": result("candidate")}],
        }
        path = self.root / "probe-results.json"
        catalog = {row_id: {"case_id": case_id, "lanes": [lane]}}
        path.write_text(json.dumps(payload), encoding="utf-8")
        with patch.object(self.generator, "API_PROBE_RESULTS_PATH", path):
            loaded = self.generator._load_validation_probe_results(catalog)
            self.assertEqual(loaded["summary"]["passed"], 1)
            payload["executions"][0]["candidate"]["stdout_sha256"] = "0" * 64
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(SystemExit, "stdout hash mismatch"):
                self.generator._load_validation_probe_results(catalog)

    def test_jvm_abi_requires_only_descriptor_evidence(self):
        row = copy.deepcopy(self.row)
        row["row_id"] = "jvm-fixture-foo"
        row["representation"] = "JVM public ABI dump"
        record = self._record(row)
        self.assertEqual(record["compatibility_obligations"], ["jvm-descriptor"])
        self.assertEqual(self._apply([record], row)["status"], "verified")

    def test_unknown_duplicate_and_malformed_evidence_is_rejected(self):
        valid = self._record()
        unknown = copy.deepcopy(valid)
        unknown["row_id"] = "unknown-row"
        malformed = copy.deepcopy(valid)
        malformed["implementation_input_sha256"] = "not-a-sha256"
        malformed_candidate = copy.deepcopy(valid)
        malformed_candidate["candidate_sha"] = "not-a-candidate-sha"
        status_only = copy.deepcopy(valid)
        status_only["status"] = "verified"
        for records in (
            [unknown],
            [valid, copy.deepcopy(valid)],
            [malformed],
            [malformed_candidate],
            [status_only],
        ):
            with self.subTest(records=records):
                with self.assertRaises(SystemExit):
                    self._apply(records)


if __name__ == "__main__":
    unittest.main()
