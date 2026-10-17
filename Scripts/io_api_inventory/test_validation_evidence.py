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
                "case_id": row["upstream_test_refs"].split(";", 1)[0],
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

    def _apply(self, records, row=None, schema_version=None, lock=None, catalogs=None):
        fixture_row = copy.deepcopy(row or self.row)
        if schema_version is None:
            schema_version = 2 if any(
                isinstance(record, dict) and "evidence_source" in record for record in records
            ) else 1
        self.evidence_path.write_text(
            json.dumps({"schema_version": schema_version, "records": records}), encoding="utf-8"
        )
        self.generator.apply_validation_evidence(
            [fixture_row], lock or self.lock, self.evidence_path, self.repository, self.upstream,
            catalogs or self._execution_catalogs(),
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

    def _special_record(self):
        row = copy.deepcopy(self.row)
        row.update({
            "row_id": self.generator.KUU_2639_ROW_ID,
            "representation": "JVM public ABI dump",
            "local_candidate_refs": "Sources/CompilerCore/Stdlib/kotlinx/io/unsafe/UnsafeBufferOperations.kt:46",
            "local_implementation_refs": "Sources/CompilerCore/Stdlib/kotlinx/io/unsafe/UnsafeBufferOperations.kt:46",
            "upstream_test_refs": self.generator.KUU_2639_CASE_ID,
            "local_test_refs": ";".join((
                self.generator.KUU_2639_CONSUMER_SOURCE,
                self.generator.KUU_2639_CONSUMER_DRIVER,
                self.generator.KUU_2639_PROBE_SOURCE,
                self.generator.KUU_2639_PROBE_EXPECTED,
                self.generator.KUU_2639_PROBE_RUNNER,
                self.generator.KUU_2639_NATIVE_SOURCE_CLOSURE,
                self.generator.KUU_2639_NATIVE_TEST_SUPPORT,
                "Scripts/io_api_inventory/run_f02_matrix.py",
            )),
        })
        source_closure = self._write(
            self.generator.KUU_2639_NATIVE_SOURCE_CLOSURE,
            json.dumps({
                "schema_version": 1,
                "upstream_commit": "362bdc35e159bad6da1e08101c8321792d762281",
                "native_execution_catalog_sha256": "3bd3e5e45e2a86315dfb7c8a5ef171abdeeab49dbc50b6260c219155b67ac57e",
                "target": "macos",
                "suites": ["kotlinx.io.unsafe.UnsafeBufferOperationsMoveTest"],
                "source_paths": ["core/common/test/unsafe/UnsafeBufferOperationsMoveTest.kt"],
            }, separators=(",", ":")) + "\n",
        )
        source_path = self.generator.KUU_2639_CASE_ID.split("#", 1)[0]
        upstream_source = self._write(source_path, "fun moveArrayFully() = Unit\n", self.upstream)
        source_blob = self.generator.git_blob_sha(upstream_source.read_bytes())
        self._write("Sources/CompilerCore/Stdlib/kotlinx/io/unsafe/UnsafeBufferOperations.kt",
                    "public fun moveToTail() = Unit\n")
        self._write(self.generator.KUU_2639_CONSUMER_SOURCE, "package probe\nfun run() = Unit\n")
        self._write(self.generator.KUU_2639_CONSUMER_DRIVER, "package probe\nfun main() = Unit\n")
        self._write(self.generator.KUU_2639_PROBE_SOURCE, "class Probe\n")
        expected_contract = {
            "row_id": self.generator.KUU_2639_ROW_ID,
            "method_shape": {"descriptor": "(Lkotlinx/io/unsafe/UnsafeBufferOperations;Lkotlinx/io/Buffer;[BIIILjava/lang/Object;)V"},
            "underlying_shape": {"descriptor": "(Lkotlinx/io/Buffer;[BII)V"},
            "default_masks": {"startIndex": 4, "endIndex": 8, "both": 12},
            "observations": [],
            "result": "PASS",
        }
        self._write(self.generator.KUU_2639_PROBE_EXPECTED,
                    json.dumps(expected_contract, separators=(",", ":")) + "\n")
        self._write(self.generator.KUU_2639_PROBE_RUNNER, "print('probe')\n")
        native_test_support = self._write(
            self.generator.KUU_2639_NATIVE_TEST_SUPPORT,
            "package kotlinx.io\nfun segmentSizes(buffer: Buffer): List<Int> = emptyList()\n"
            "fun assertArrayEquals(a: ByteArray, b: ByteArray) = Unit\n",
        )
        self._write("Scripts/io_api_inventory/run_f02_matrix.py", "print('matrix')\n")
        self._write("Scripts/kotlinx_io_upstream/reference-lock.json", json.dumps({
            "jvm_artifacts": [{
                "coordinate": "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1",
                "sha256": "b" * 64,
            }],
            "upstream_files": [{"path": source_path, "git_blob_sha": source_blob}],
        }))
        io_lock = {
            **self.lock,
            "upstreamTests": [{"path": source_path, "gitBlobSha": source_blob}],
        }

        record = self._record(row)
        catalogs = {"reference": {}, "candidate": {}}
        for index, execution in enumerate(record["executions"]):
            catalogs["reference"][execution["reference"]["execution_id"]] = self.generator.KUU_2639_CASE_ID
            catalogs["candidate"][execution["candidate"]["execution_id"]] = self.generator.KUU_2639_CASE_ID
        reference_id = record["executions"][0]["reference"]["execution_id"]
        report = {
            "schema_version": 1,
            "kind": "locked-upstream-jvm-test",
            "upstream_id": self.generator.KUU_2639_CASE_ID,
            "execution_id": reference_id,
            "reference_version": self.lock["tag"],
            "reference_commit": self.lock["commit"],
            "test_source_path": source_path,
            "test_source_sha256": hashlib.sha256(upstream_source.read_bytes()).hexdigest(),
            "test_source_git_blob_sha": source_blob,
            "support_sources": [],
            "selected_method_source_sha256": "c" * 64,
            "prepared_source_sha256": "d" * 64,
            "result": "PASS",
            "exit_code": 0,
            "discovered_count": 1,
            "executed_count": 1,
            "passed_count": 1,
            "java_runtime_major": 21,
            "java_version_sha256": "9" * 64,
            "jvm_artifact_sha256": {"kotlinx-io-core-jvm-0.9.1.jar": "b" * 64},
        }
        expected_path = self.repository / self.generator.KUU_2639_PROBE_EXPECTED
        expected_contract = json.loads(expected_path.read_text())
        probe_report = {
            "schema_version": 1,
            "probe_id": "JVMABIReflectionLedgerProbe#" + self.generator.KUU_2639_ROW_ID,
            "row_id": self.generator.KUU_2639_ROW_ID,
            "candidate_sha": record["candidate_sha"],
            "reference_version": self.lock["tag"],
            "reference_commit": self.lock["commit"],
            "artifact_coordinate": "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1",
            "artifact_sha256": "b" * 64,
            "probe_source_path": self.generator.KUU_2639_PROBE_SOURCE,
            "probe_source_sha256": hashlib.sha256(
                (self.repository / self.generator.KUU_2639_PROBE_SOURCE).read_bytes()
            ).hexdigest(),
            "expected_contract_path": self.generator.KUU_2639_PROBE_EXPECTED,
            "expected_contract_sha256": hashlib.sha256(expected_path.read_bytes()).hexdigest(),
            "probe_stdout_sha256": "c" * 64,
            "probe_stderr_sha256": "d" * 64,
            "java_runtime_major": 21,
            "java_version_sha256": "9" * 64,
            "probe": {**expected_contract, "assertion_count": 20},
            "result": "PASS",
            "exit_code": 0,
        }
        scenario_hashes = {
            relative: hashlib.sha256((self.repository / relative).read_bytes()).hexdigest()
            for relative in (self.generator.KUU_2639_CONSUMER_SOURCE,
                             self.generator.KUU_2639_CONSUMER_DRIVER)
        }
        matrix_summary = {
            "status": "SELECTED_MATRIX_PASS",
            "workspace_git_sha": record["candidate_sha"],
            "selected_cases": [self.generator.KUU_2639_CONSUMER_CASE_ID],
            "issue_complete": False,
            "scenario_files_sha256": scenario_hashes,
            "results": [{
                "case": self.generator.KUU_2639_CONSUMER_CASE_ID,
                "route": route,
                "optimization": optimization,
                "status": "PASS",
                "stdout_sha256": "e" * 64,
                "normalized_stdout_sha256": "f" * 64,
            } for route in ("source", "stdlib-library", "producer-consumer")
              for optimization in ("O0", "O2")],
        }
        candidate_receipts = [{
            "lane": execution["lane"],
            "execution_id": execution["candidate"]["execution_id"],
            "result": "PASS",
            "exit_code": 0,
            "selected_count": 1,
            "passed_count": 1,
            "run_stdout_sha256": "1" * 64,
            "run_stderr_sha256": "2" * 64,
            "results_sha256": "3" * 64,
            "summary_sha256": "4" * 64,
            "executable_sha256": "5" * 64,
            "runner_inputs_sha256": "6" * 64,
            "test_support_source_sha256": hashlib.sha256(native_test_support.read_bytes()).hexdigest(),
        } for execution in record["executions"]]
        record["specialized_evidence"] = {
            "policy": self.generator.KUU_2639_SPECIAL_EVIDENCE_POLICY,
            "native_source_closure_sha256": hashlib.sha256(source_closure.read_bytes()).hexdigest(),
            "native_test_support_sha256": hashlib.sha256(native_test_support.read_bytes()).hexdigest(),
            "upstream_jvm_case": report,
            "jvm_bridge_probe": {
                "report_sha256": self.generator.canonical_json_sha256(probe_report),
                "report": probe_report,
            },
            "candidate_lane_receipts": candidate_receipts,
            "dedicated_consumer_matrix": {
                "summary_sha256": self.generator.canonical_json_sha256(matrix_summary),
                "summary": matrix_summary,
            },
        }
        record["evidence_source"] = "upstream-catalog"
        return row, record, io_lock, catalogs

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

    def test_kuu2639_checks_specialized_receipts_but_keeps_jvm_row_unverified(self):
        row, record, lock, catalogs = self._special_record()
        self.assertEqual(
            record["compatibility_obligations"], ["native-source", "native-bridge"]
        )
        self.assertEqual(
            self._apply([record], row, lock=lock, catalogs=catalogs)["status"], "unverified"
        )

    def test_kuu2639_rejects_missing_consumer_lane_and_changed_bridge_contract(self):
        row, record, lock, catalogs = self._special_record()
        missing_lane = copy.deepcopy(record)
        consumer = missing_lane["specialized_evidence"]["dedicated_consumer_matrix"]
        consumer["summary"]["results"].pop()
        consumer["summary_sha256"] = self.generator.canonical_json_sha256(consumer["summary"])
        with self.assertRaisesRegex(SystemExit, "missing a required route/optimization lane"):
            self._apply([missing_lane], row, lock=lock, catalogs=catalogs)

        changed_contract = copy.deepcopy(record)
        bridge = changed_contract["specialized_evidence"]["jvm_bridge_probe"]
        bridge["report"]["probe"]["method_shape"]["descriptor"] = "(wrong)V"
        bridge["report_sha256"] = self.generator.canonical_json_sha256(bridge["report"])
        with self.assertRaisesRegex(SystemExit, "output differs from its locked contract"):
            self._apply([changed_contract], row, lock=lock, catalogs=catalogs)

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
