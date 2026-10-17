#!/usr/bin/env python3
"""Exercise validation evidence application with a one-row inventory fixture."""

import copy
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

    def _apply(self, records, row=None, schema_version=1, execution_catalogs=None):
        fixture_row = copy.deepcopy(row or self.row)
        self.evidence_path.write_text(
            json.dumps({"schema_version": schema_version, "records": records}), encoding="utf-8"
        )
        self.generator.apply_validation_evidence(
            [fixture_row], self.lock, self.evidence_path, self.repository, self.upstream,
            execution_catalogs or self._execution_catalogs(),
        )
        return fixture_row

    def _local_probe_row(self):
        row = copy.deepcopy(self.row)
        row.update(
            row_id="internal-7f39deeafb60d29d",
            local_candidate_refs="Sources/CompilerCore/Stdlib/kotlinx/io/Foo.kt:1",
            local_implementation_refs="Sources/CompilerCore/Stdlib/kotlinx/io/Foo.kt:1",
            local_test_refs=(
                "Scripts/io_api_inventory/probes/segment_data_as_byte_array.kt;"
                "Scripts/io_api_inventory/probes/segment_data_as_byte_array_negative.kt"
            ),
        )
        self._write(
            "Scripts/io_api_inventory/probes/segment_data_as_byte_array.kt",
            "fun main() = check(true)\n",
        )
        self._write(
            "Scripts/io_api_inventory/probes/segment_data_as_byte_array_negative.kt",
            "fun main() = check(true)\n",
        )
        return row

    def _local_probe_record(self, row):
        candidate_sha = "a" * 40
        executions = []
        cases = [
            case_id for case_id, spec in self.generator.LOCAL_PROBE_EVIDENCE_CASES.items()
            if row["row_id"] in spec["row_ids"]
            and spec["path"] in row["local_test_refs"].split(";")
        ]
        for case_id in cases:
            spec = self.generator.LOCAL_PROBE_EVIDENCE_CASES[case_id]
            for lane in spec["lanes"]:
                executions.append({
                    "case_id": case_id,
                    "lane": lane,
                    **{
                        subject: {
                            "execution_id": self.generator.local_probe_execution_id(
                                candidate_sha, self.lock["commit"], case_id, lane, subject
                            ),
                            "result": "PASS",
                            "exit_code": 0,
                            "method": spec["methods"][subject],
                        }
                        for subject in ("reference", "candidate")
                    },
                })
        return {
            "row_id": row["row_id"],
            "candidate_sha": candidate_sha,
            "reference_version": self.lock["tag"],
            "reference_commit": self.lock["commit"],
            **self.generator.validation_input_hashes(row, self.repository, self.upstream),
            "compatibility_obligations": self.generator.validation_obligations(row),
            "evidence_source": "local-probe",
            "executions": executions,
        }

    def _buffer_hint_probe_row(self, row_id):
        case_specs = [
            (case_id, spec) for case_id, spec in self.generator.LOCAL_PROBE_EVIDENCE_CASES.items()
            if row_id in spec["row_ids"]
        ]
        self.assertEqual(len(case_specs), 1)
        case_id, spec = case_specs[0]
        inputs = [spec["path"], *spec.get("inputs", ())]
        local_refs = inputs
        for relative in set(inputs):
            self._write(relative, "fixture input\n")
        row = copy.deepcopy(self.row)
        row.update(
            row_id=row_id,
            representation=("JVM public ABI dump" if row_id.startswith("jvm-")
                            else "Kotlin source API / KLIB dump"),
            local_test_refs=";".join(local_refs),
        )
        record = self._local_probe_record(row)
        catalogs = self._execution_catalogs()
        for execution in record["executions"]:
            for subject in ("reference", "candidate"):
                receipt = {
                    "case_id": execution["case_id"],
                    "lane": execution["lane"],
                    "method": execution[subject]["method"],
                    "result": "PASS",
                    "exit_code": 0,
                    "candidate_sha": record["candidate_sha"],
                    "command_sha256": "a" * 64,
                    "stdout_sha256": "b" * 64,
                    "stderr_sha256": "c" * 64,
                    "stdout_bytes": 1,
                    "stderr_bytes": 0,
                }
                catalogs[subject][execution[subject]["execution_id"]] = receipt
        for case_id, spec in case_specs:
            for supplemental in spec.get("supplemental_receipts", ()):
                subject = supplemental["subject"]
                supplemental_case_id = supplemental.get("case_id", case_id)
                execution_id = self.generator.local_probe_execution_id(
                    record["candidate_sha"], self.lock["commit"], supplemental_case_id,
                    supplemental["lane"], subject,
                )
                catalogs[subject][execution_id] = {
                    "case_id": supplemental_case_id,
                    "lane": supplemental["lane"],
                    "method": supplemental["method"],
                    "result": supplemental.get("result", "PASS"),
                    "exit_code": supplemental.get("exit_code", 0),
                    "candidate_sha": record["candidate_sha"],
                    "command_sha256": "d" * 64,
                    "stdout_sha256": "b" * 64,
                    "stderr_sha256": "c" * 64,
                    "stdout_bytes": 1,
                    "stderr_bytes": 0,
                }
        return row, record, catalogs

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

    def test_schema_v2_upstream_catalog_records_keep_the_locked_mapping(self):
        record = self._record()
        record["evidence_source"] = "upstream-catalog"
        self.assertEqual(self._apply([record], schema_version=2)["status"], "verified")

    def test_registered_local_probe_evidence_promotes_only_its_row(self):
        row = self._local_probe_row()
        record = self._local_probe_record(row)
        self.assertEqual(self._apply([record], row, schema_version=2)["status"], "verified")

    def test_buffer_hint_emit_probe_is_registered_to_the_two_owned_rows(self):
        for row_id in ("jvm-23aa7a8f63c07fd5", "klib-6ec3d2252d99b756"):
            with self.subTest(row_id=row_id):
                cases = {
                    case_id: spec for case_id, spec in self.generator.LOCAL_PROBE_EVIDENCE_CASES.items()
                    if row_id in spec["row_ids"]
                }
                self.assertEqual(len(cases), 1)
                spec = next(iter(cases.values()))
                self.assertTrue(spec["receipt_catalog"])
                self.assertIn("Tests/CompilerCoreTests/Sema/KotlinxIOBufferHintEmitContractTests.swift", spec["inputs"])
        unrelated = {
            "_candidate_name": "hintEmit",
            "owner_fqn": "kotlinx.io/Buffer",
            "module": "core",
            "row_id": "klib-unrelated-buffer",
        }
        references = self.generator.local_test_refs(unrelated, [
            ("Tests/CompilerBackendTests/Fixtures/IOBufferHintEmit2604/BufferHintEmitConsumer.kt", "hintEmit()"),
            ("Tests/CompilerCoreTests/Sema/KotlinxIOBufferHintEmitContractTests.swift", "hintEmit()"),
        ])
        self.assertFalse(any("BufferHintEmit2604" in reference for reference in references))
        self.assertNotIn("Tests/CompilerCoreTests/Sema/KotlinxIOBufferHintEmitContractTests.swift", references)

    def test_buffer_hint_emit_evidence_requires_matching_lane_receipts(self):
        row, record, catalogs = self._buffer_hint_probe_row("klib-6ec3d2252d99b756")
        self.assertEqual(self._apply([record], row, schema_version=2, execution_catalogs=catalogs)["status"], "verified")
        missing = copy.deepcopy(catalogs)
        execution_id = record["executions"][0]["candidate"]["execution_id"]
        missing["candidate"].pop(execution_id)
        with self.assertRaisesRegex(SystemExit, "missing candidate local execution receipt"):
            self._apply([record], row, schema_version=2, execution_catalogs=missing)
        wrong_lane = copy.deepcopy(catalogs)
        wrong_lane["candidate"][execution_id]["lane"] = "source-O2"
        with self.assertRaisesRegex(SystemExit, "different case or lane"):
            self._apply([record], row, schema_version=2, execution_catalogs=wrong_lane)
        missing_native = copy.deepcopy(catalogs)
        case_id = next(case_id for case_id, spec in self.generator.LOCAL_PROBE_EVIDENCE_CASES.items()
                       if row["row_id"] in spec["row_ids"] and spec.get("supplemental_receipts"))
        spec = self.generator.LOCAL_PROBE_EVIDENCE_CASES[case_id]
        supplemental = spec["supplemental_receipts"][0]
        native_id = self.generator.local_probe_execution_id(
            record["candidate_sha"], self.lock["commit"], case_id,
            supplemental["lane"], supplemental["subject"],
        )
        missing_native[supplemental["subject"]].pop(native_id)
        with self.assertRaisesRegex(SystemExit, "missing reference supplemental local receipt"):
            self._apply([record], row, schema_version=2, execution_catalogs=missing_native)

    def test_buffer_hint_emit_jvm_negative_opt_in_receipt_requires_rejection(self):
        row, record, catalogs = self._buffer_hint_probe_row("jvm-23aa7a8f63c07fd5")
        self.assertEqual(self._apply([record], row, schema_version=2, execution_catalogs=catalogs)["status"], "verified")
        case_id = next(case_id for case_id, spec in self.generator.LOCAL_PROBE_EVIDENCE_CASES.items()
                       if row["row_id"] in spec["row_ids"])
        supplemental = self.generator.LOCAL_PROBE_EVIDENCE_CASES[case_id]["supplemental_receipts"][0]
        execution_id = self.generator.local_probe_execution_id(
            record["candidate_sha"], self.lock["commit"], case_id,
            supplemental["lane"], supplemental["subject"],
        )
        wrong_exit = copy.deepcopy(catalogs)
        wrong_exit["candidate"][execution_id]["exit_code"] = 0
        with self.assertRaisesRegex(SystemExit, "invalid candidate supplemental local receipt"):
            self._apply([record], row, schema_version=2, execution_catalogs=wrong_exit)

    def test_local_probe_evidence_rejects_unregistered_cases_and_forged_ids(self):
        row = self._local_probe_row()
        valid = self._local_probe_record(row)
        wrong_case = copy.deepcopy(valid)
        wrong_case["executions"][0]["case_id"] = "local:core/common/test/FooTest.kt#testFoo"
        wrong_id = copy.deepcopy(valid)
        wrong_id["executions"][0]["candidate"]["execution_id"] = "candidate-is-not-a-probe"
        wrong_method = copy.deepcopy(valid)
        wrong_method["executions"][0]["candidate"]["method"] = "jvm-abi-reflection"
        for record in (wrong_case, wrong_id, wrong_method):
            with self.subTest(record=record):
                with self.assertRaises(SystemExit):
                    self._apply([record], row, schema_version=2)

    def test_local_probe_evidence_requires_each_registered_case_and_lane(self):
        row = self._local_probe_row()
        record = self._local_probe_record(row)
        record["executions"] = [
            execution for execution in record["executions"]
            if not (
                execution["case_id"].endswith("#internal-visibility")
                and execution["lane"] == "producer-consumer-O2"
            )
        ]
        with self.assertRaisesRegex(SystemExit, "missing local probe lanes"):
            self._apply([record], row, schema_version=2)

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
