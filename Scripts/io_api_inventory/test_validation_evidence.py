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
        self._write(
            "Scripts/io_api_inventory/f02_consumers/ByteStringSyntheticConstructorConsumer.kt",
            "fun main() = Unit\n",
        )
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
            | {"reference-wrong": other_case_id, "probe-reference": "Scripts/io_api_inventory/f02_consumers/ByteStringSyntheticConstructorConsumer.kt#main"},
            "candidate": {f"candidate-{index}": case_id for index in range(6)}
            | {"candidate-wrong": other_case_id, "probe-candidate": "Scripts/io_api_inventory/f02_consumers/ByteStringSyntheticConstructorConsumer.kt#main"},
        }

    def _apply(self, records, row=None, schema_version=1):
        fixture_row = copy.deepcopy(row or self.row)
        self.evidence_path.write_text(
            json.dumps({"schema_version": schema_version, "records": records}), encoding="utf-8"
        )
        self.generator.apply_validation_evidence(
            [fixture_row], self.lock, self.evidence_path, self.repository, self.upstream,
            self._execution_catalogs(),
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

    def test_indexof_default_bridges_require_reference_and_native_source_lanes(self):
        for jvm_key in self.generator.INDEX_OF_DEFAULT_BRIDGES:
            with self.subTest(jvm_key=jvm_key):
                row = {
                    "row_id": self.generator.INDEX_OF_DEFAULT_BRIDGES[jvm_key]["row_id"],
                    "representation": "JVM public ABI dump",
                    "_jvm_key": jvm_key,
                }
                obligations = self.generator.validation_obligations(row)
                self.assertEqual(obligations, ["jvm-descriptor", "native-source"])
                self.assertEqual(
                    self.generator.required_execution_lanes(obligations),
                    [
                        "jvm-descriptor",
                        "source-O0",
                        "source-O2",
                        "stdlib-library-O0",
                        "stdlib-library-O2",
                    ],
                )

    def test_indexof_default_bridge_obligations_restore_from_tsv_row_id(self):
        for jvm_key, spec in self.generator.INDEX_OF_DEFAULT_BRIDGES.items():
            with self.subTest(row_id=spec["row_id"]):
                row = self.generator.restore_hidden_jvm_key({"row_id": spec["row_id"]})
                self.assertEqual(row["_jvm_key"], jvm_key)
                self.assertEqual(
                    self.generator.required_execution_lanes(
                        self.generator.validation_obligations(row)
                    ),
                    [
                        "jvm-descriptor",
                        "source-O0",
                        "source-O2",
                        "stdlib-library-O0",
                        "stdlib-library-O2",
                    ],
                )

    def test_indexof_default_bridge_probe_report_is_current_and_passed(self):
        for jvm_key, spec in self.generator.INDEX_OF_DEFAULT_BRIDGES.items():
            with self.subTest(row_id=spec["row_id"]):
                row = {"row_id": spec["row_id"], "_jvm_key": jvm_key}
                record = {"candidate_sha": "fd01a5e98145e8295e5b299b0a7190cc8d44e3a7"}
                self.generator.validate_index_of_bridge_probe(
                    row, record, self.generator.REPO
                )

    def test_dedicated_local_probe_can_cover_a_jvm_descriptor_without_upstream_test_refs(self):
        row = copy.deepcopy(self.row)
        row["row_id"] = "jvm-fixture-foo"
        row["representation"] = "JVM public ABI dump"
        row["upstream_test_refs"] = self.generator.NO_DIRECT_UPSTREAM_ASSERTION
        row["local_test_refs"] = "Scripts/io_api_inventory/f02_consumers/ByteStringSyntheticConstructorConsumer.kt"
        record = self._record(row)
        case_id = "Scripts/io_api_inventory/f02_consumers/ByteStringSyntheticConstructorConsumer.kt#main"
        record["executions"][0].update(
            case_id=case_id,
            reference={"execution_id": "probe-reference", "result": "PASS", "exit_code": 0},
            candidate={"execution_id": "probe-candidate", "result": "PASS", "exit_code": 0},
        )
        self.assertEqual(self._apply([record], row)["status"], "verified")

    def test_local_probe_execution_catalog_uses_its_inventory_lock_hash(self):
        reference_path = self.root / "reference-executions.json"
        candidate_path = self.root / "candidate-executions.json"
        probe_path = self.root / "probe-executions.json"
        runner_lock_path = self.root / "runner-lock.json"
        reference_bytes = b"[]\n"
        candidate_bytes = b"[]\n"
        probe_bytes = json.dumps({
            "schema_version": 1,
            "probes": [{
                "case_id": "Scripts/io_api_inventory/f02_consumers/ByteStringSyntheticConstructorConsumer.kt#main",
                "reference_execution_id": "probe-reference",
                "candidate_execution_id": "probe-candidate",
            }],
        }, indent=2).encode("utf-8") + b"\n"
        reference_path.write_bytes(reference_bytes)
        candidate_path.write_bytes(candidate_bytes)
        probe_path.write_bytes(probe_bytes)
        runner_lock_path.write_text(json.dumps({
            "commit": self.generator.EXPECTED_TAG_COMMIT,
            "jvm_execution_catalog_sha256": hashlib.sha256(reference_bytes).hexdigest(),
            "native_execution_catalog_sha256": hashlib.sha256(candidate_bytes).hexdigest(),
        }), encoding="utf-8")
        with (
            patch.object(self.generator, "UPSTREAM_RUNNER_LOCK_PATH", runner_lock_path),
            patch.object(self.generator, "REFERENCE_EXECUTIONS_PATH", reference_path),
            patch.object(self.generator, "CANDIDATE_EXECUTIONS_PATH", candidate_path),
            patch.object(self.generator, "VALIDATION_PROBE_EXECUTIONS_PATH", probe_path),
        ):
            catalogs = self.generator._load_validation_execution_catalogs({
                "validationProbeExecutionsSha256": hashlib.sha256(probe_bytes).hexdigest(),
            })
            self.assertEqual(
                catalogs["reference"]["probe-reference"],
                "Scripts/io_api_inventory/f02_consumers/ByteStringSyntheticConstructorConsumer.kt#main",
            )
            self.assertEqual(
                catalogs["candidate"]["probe-candidate"],
                "Scripts/io_api_inventory/f02_consumers/ByteStringSyntheticConstructorConsumer.kt#main",
            )
            with self.assertRaises(SystemExit):
                self.generator._load_validation_execution_catalogs({
                    "validationProbeExecutionsSha256": "0" * 64,
                })

    def test_local_probe_cannot_replace_a_mapped_upstream_assertion(self):
        row = copy.deepcopy(self.row)
        record = self._record(row)
        record["executions"][0]["case_id"] = (
            "Scripts/io_api_inventory/f02_consumers/ByteStringSyntheticConstructorConsumer.kt#main"
        )
        record["executions"][0]["reference"]["execution_id"] = "probe-reference"
        record["executions"][0]["candidate"]["execution_id"] = "probe-candidate"
        with self.assertRaisesRegex(SystemExit, "is not mapped to row"):
            self._apply([record], row)

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
