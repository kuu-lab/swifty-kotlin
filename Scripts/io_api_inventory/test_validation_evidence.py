#!/usr/bin/env python3
"""Exercise validation evidence application with a one-row inventory fixture."""

import copy
import hashlib
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
        self.probe_case_id = "Scripts/io_api_inventory/probes/FooProbe.kt#fooProbe"
        self._write("Scripts/io_api_inventory/probes/FooProbe.kt", "fun fooProbe() = check(foo() == 1)\n")
        self.jvm_probe_case_id = "Scripts/io_api_inventory/probes/FooJvmProbe.java#main"
        self._write("Scripts/io_api_inventory/probes/FooJvmProbe.java", "final class FooJvmProbe { public static void main(String[] args) {} }\n")
        self._write("Scripts/io_api_inventory/validation-probe-refs.json", json.dumps({
            "schema_version": 1,
            "probes": [
                {
                    "case_id": self.probe_case_id,
                    "row_ids": ["klib-fixture-foo"],
                    "input_files": ["Scripts/io_api_inventory/probes/FooProbe.kt"],
                    "kind": "reference-and-candidate",
                    "candidate_not_applicable_reason": None,
                },
                {
                    "case_id": self.jvm_probe_case_id,
                    "row_ids": ["jvm-fixture-foo"],
                    "input_files": ["Scripts/io_api_inventory/probes/FooJvmProbe.java"],
                    "kind": "reference-only-jvm-descriptor",
                    "candidate_not_applicable_reason": self.generator.JVM_NATIVE_EMISSION_NOT_APPLICABLE,
                },
            ],
        }))
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

    def _record(self, row=None, case_id="core/common/test/FooTest.kt#testFoo",
                candidate_sha="a" * 40, candidate_not_applicable_reason=None):
        row = row or self.row
        executions = []
        lanes = self.generator.required_execution_lanes(self.generator.validation_obligations(row))
        for index, lane in enumerate(lanes):
            local_probe = case_id.startswith("Scripts/")
            reference_id = f"probe-reference-{index}" if local_probe else f"reference-{index}"
            candidate_id = f"probe-candidate-{index}" if local_probe else f"candidate-{index}"
            candidate = {"execution_id": candidate_id, "result": "PASS", "exit_code": 0}
            if candidate_not_applicable_reason is not None:
                candidate = {
                    "execution_id": None,
                    "result": "NOT_APPLICABLE",
                    "exit_code": None,
                    "reason": candidate_not_applicable_reason,
                }
            executions.append({
                "case_id": case_id,
                "lane": lane,
                "reference": {
                    "execution_id": reference_id,
                    "result": "PASS",
                    "exit_code": 0,
                },
                "candidate": candidate,
            })
        return {
            "row_id": row["row_id"],
            "candidate_sha": candidate_sha,
            "reference_version": self.lock["tag"],
            "reference_commit": self.lock["commit"],
            **self.generator.validation_input_hashes(row, self.repository, self.upstream),
            "compatibility_obligations": self.generator.validation_obligations(row),
            "executions": executions,
        }

    def _execution_catalogs(self, probe_case_id=None, lanes=(), candidate_sha="a" * 40,
                            candidate_not_applicable=False):
        upstream_case_id = "core/common/test/FooTest.kt#testFoo"
        other_case_id = "core/common/test/BarTest.kt#testBar"
        catalogs = {
            "reference": {f"reference-{index}": upstream_case_id for index in range(6)}
            | {"reference-wrong": other_case_id},
            "candidate": {f"candidate-{index}": upstream_case_id for index in range(6)}
            | {"candidate-wrong": other_case_id},
            "probe_reference": {},
            "probe_candidate": {},
        }
        if probe_case_id:
            for index, lane in enumerate(lanes):
                reference_id = f"probe-reference-{index}"
                metadata = {
                    "execution_id": reference_id,
                    "case_id": probe_case_id,
                    "lane": lane,
                    "result": "PASS",
                    "exit_code": 0,
                    "stdout_sha256": "b" * 64,
                    "normalized_stdout_sha256": "e" * 64,
                    "stderr_sha256": "c" * 64,
                    "probe_input_sha256": hashlib.sha256(
                        (self.repository / probe_case_id.split("#", 1)[0]).read_bytes()
                    ).hexdigest(),
                    "candidate_sha": candidate_sha,
                    "reference_commit": self.lock["commit"],
                }
                catalogs["reference"][reference_id] = probe_case_id
                catalogs["probe_reference"][reference_id] = metadata
                if not candidate_not_applicable:
                    candidate_id = f"probe-candidate-{index}"
                    catalogs["candidate"][candidate_id] = probe_case_id
                    catalogs["probe_candidate"][candidate_id] = {**metadata, "execution_id": candidate_id}
        return catalogs

    def _apply(self, records, row=None, execution_catalogs=None):
        fixture_row = copy.deepcopy(row or self.row)
        self.evidence_path.write_text(json.dumps({
            "schema_version": self.generator.VALIDATION_EVIDENCE_SCHEMA_VERSION,
            "records": records,
        }), encoding="utf-8")
        self.generator.apply_validation_evidence(
            [fixture_row], self.lock, self.evidence_path, self.repository, self.upstream,
            execution_catalogs or self._execution_catalogs(),
        )
        return fixture_row

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
            "Scripts/io_api_inventory/probes/FooProbe.kt",
        ):
            with self.subTest(relative=relative):
                record = self._record()
                path = self.repository / relative
                path.write_text(path.read_text(encoding="utf-8") + "// changed\n", encoding="utf-8")
                with self.assertRaises(SystemExit):
                    self._apply([record])
                path.write_text(path.read_text(encoding="utf-8").replace("// changed\n", ""), encoding="utf-8")

    def test_direct_probe_must_be_registered_for_this_row_and_receipted(self):
        record = self._record(case_id=self.probe_case_id)
        lanes = [execution["lane"] for execution in record["executions"]]
        catalogs = self._execution_catalogs(self.probe_case_id, lanes, record["candidate_sha"])
        self.assertEqual(self._apply([record], execution_catalogs=catalogs)["status"], "verified")

        stale_receipt = copy.deepcopy(catalogs)
        stale_receipt["probe_candidate"]["probe-candidate-0"]["candidate_sha"] = "d" * 40
        with self.assertRaisesRegex(SystemExit, "receipt does not match"):
            self._apply([record], execution_catalogs=stale_receipt)

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

    def test_jvm_abi_requires_only_descriptor_evidence(self):
        row = copy.deepcopy(self.row)
        row["row_id"] = "jvm-fixture-foo"
        row["representation"] = "JVM public ABI dump"
        record = self._record(
            row,
            case_id=self.jvm_probe_case_id,
            candidate_not_applicable_reason=self.generator.JVM_NATIVE_EMISSION_NOT_APPLICABLE,
        )
        self.assertEqual(record["compatibility_obligations"], ["jvm-descriptor"])
        catalogs = self._execution_catalogs(
            self.jvm_probe_case_id,
            ["jvm-descriptor"],
            record["candidate_sha"],
            candidate_not_applicable=True,
        )
        result = self._apply([record], row, catalogs)
        self.assertEqual(result["status"], "unverified")

        wrong_reason = self._record(
            row,
            case_id=self.jvm_probe_case_id,
            candidate_not_applicable_reason="not available",
        )
        with self.assertRaisesRegex(SystemExit, "not applicable only"):
            self._apply([wrong_reason], row, catalogs)

    def test_candidate_not_applicable_cannot_skip_a_native_lane(self):
        record = self._record(
            case_id=self.probe_case_id,
            candidate_not_applicable_reason=self.generator.JVM_NATIVE_EMISSION_NOT_APPLICABLE,
        )
        lanes = [execution["lane"] for execution in record["executions"]]
        catalogs = self._execution_catalogs(self.probe_case_id, lanes, record["candidate_sha"])
        with self.assertRaisesRegex(SystemExit, "not applicable only"):
            self._apply([record], execution_catalogs=catalogs)

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
