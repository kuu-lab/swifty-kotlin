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
        catalogs = {
            "reference": {f"reference-{index}": case_id for index in range(6)}
            | {"reference-wrong": other_case_id},
            "candidate": {f"candidate-{index}": case_id for index in range(6)}
            | {"candidate-wrong": other_case_id},
        }
        method_names = (
            "writeUtf8FromIndex",
            "writeUtf8WithInvalidIndexes",
            "writeCharSequenceFromIndex",
            "writeCharSequenceWithInvalidIndexes",
        )
        for concrete_class in ("BufferSinkTest", "RealSinkTest"):
            for method_name in method_names:
                upstream_id = f"core/common/test/AbstractSinkTest.kt#{method_name}"
                reference_id = (
                    f"[engine:junit-jupiter]/[class:kotlinx.io.{concrete_class}]"
                    f"/[method:{method_name}()]"
                )
                native_id = f"kotlinx.io.{concrete_class}.{method_name}"
                catalogs["reference"][reference_id] = upstream_id
                catalogs["candidate"][native_id] = upstream_id
        return catalogs

    def _apply(self, records, row=None, reference_observations=None, schema_version=1, upstream=None):
        fixture_row = copy.deepcopy(row or self.row)
        evidence = {"schema_version": schema_version, "records": records}
        if reference_observations is not None:
            evidence["reference_observations"] = reference_observations
        self.evidence_path.write_text(json.dumps(evidence), encoding="utf-8")
        self.generator.apply_validation_evidence(
            [fixture_row], self.lock, self.evidence_path, self.repository, upstream or self.upstream,
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

    def _sink_write_string_observation(self, is_char_sequence=False):
        string_case = (
            "core/common/test/AbstractSinkTest.kt#writeUtf8FromIndex",
            "core/common/test/AbstractSinkTest.kt#writeUtf8WithInvalidIndexes",
        )
        char_sequence_case = (
            "core/common/test/AbstractSinkTest.kt#writeCharSequenceFromIndex",
            "core/common/test/AbstractSinkTest.kt#writeCharSequenceWithInvalidIndexes",
        )
        row_id = (
            "jvm-804266071f0ab846" if is_char_sequence else "jvm-2a9d7e102164fbd2"
        )
        case_ids = char_sequence_case if is_char_sequence else string_case
        method_names = [case_id.rsplit("#", 1)[1] for case_id in case_ids]
        method = {
            "name": "writeString$default",
            "descriptor": (
                "(Lkotlinx/io/Sink;Ljava/lang/CharSequence;IIILjava/lang/Object;)V"
                if is_char_sequence else
                "(Lkotlinx/io/Sink;Ljava/lang/String;IIILjava/lang/Object;)V"
            ),
            "flags": {"public": True, "static": True, "synthetic": True, "bridge": False},
            "default_mask_values_when_both_indices_are_omitted": [6],
            "marker_parameter": "java.lang.Object",
        }
        fixture_row = copy.deepcopy(self.row)
        fixture_row.update({
            "row_id": row_id,
            "representation": "JVM public ABI dump",
            "name": "writeString$default",
            "signature": "public static synthetic fun writeString$default " + method["descriptor"],
            "upstream_test_refs": ";".join(case_ids),
            "local_candidate_refs": "Sources/CompilerCore/Stdlib/kotlinx/io/Utf8.kt:16",
            "local_implementation_refs": "Sources/CompilerCore/Stdlib/kotlinx/io/Utf8.kt:16",
            "owner_fqn": "kotlinx/io/Utf8Kt",
            "_inventory_status": "unverified",
            "_jvm_key": (
                "core",
                "kotlinx/io/Utf8Kt",
                "writeString$default",
                "(Lkotlinx/io/Sink;Ljava/lang/CharSequence;IIILjava/lang/Object;)V"
                if is_char_sequence else
                "(Lkotlinx/io/Sink;Ljava/lang/String;IIILjava/lang/Object;)V",
            ),
        })
        self._write(
            "Sources/CompilerCore/Stdlib/kotlinx/io/Utf8.kt",
            "fun writeString() = Unit\n",
        )
        executions = []
        for concrete_class in ("BufferSinkTest", "RealSinkTest"):
            for method_name, case_id in zip(method_names, case_ids):
                execution_id = (
                    f"[engine:junit-jupiter]/[class:kotlinx.io.{concrete_class}]"
                    f"/[method:{method_name}()]"
                )
                executions.append({
                    "case_id": case_id,
                    "lane": "jvm-descriptor",
                    "reference": {"execution_id": execution_id, "result": "PASS", "exit_code": 0},
                })
        native_ids = [
            f"kotlinx.io.{concrete_class}.{method_name}"
            for concrete_class in ("BufferSinkTest", "RealSinkTest")
            for method_name in method_names
        ]
        consumer_lanes = []
        for lane in self.generator.REFERENCE_OBSERVATION_CONSUMER_LANES:
            digest = "a" * 64
            consumer_lanes.append({
                "lane": lane,
                "result": "PASS",
                "exit_code": 0,
                "reference_normalized_stdout_sha256": digest,
                "candidate_stdout_sha256": "b" * 64,
                "candidate_normalized_stdout_sha256": digest,
            })
        return fixture_row, {
            "row_id": row_id,
            "candidate_sha": self.generator.KUU_2634_CANDIDATE_SHA,
            "reference_version": self.lock["tag"],
            "reference_commit": self.lock["commit"],
            **self.generator.validation_input_hashes(
                fixture_row, self.repository, self.generator.UPSTREAM
            ),
            "compatibility_obligations": ["jvm-descriptor"],
            "executions": executions,
            "candidate_execution_kind": "macOS-native-direct-assertions",
            "non_promotion_reason": "The candidate emits native code and has no JVM classfile to compare.",
            "reference_abi_probe": {
                "result": "PASS",
                "artifact_coordinate": "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1",
                "artifact_sha256": "c" * 64,
                "class": "kotlinx/io/Utf8Kt.class",
                "class_sha256": "d" * 64,
                "probe_sha256": "e" * 64,
                "method": method,
                "implementation_opt_ins_match": True,
                "documented_exception_types": [
                    "IndexOutOfBoundsException",
                    "IllegalArgumentException",
                    "IllegalStateException",
                    "IOException",
                ],
            },
            "native_assertion_runs": [
                {
                    "lane": lane,
                    "result": "PASS",
                    "execution_count": len(native_ids),
                    "execution_ids": native_ids,
                    "summary_sha256": "f" * 64,
                    "compiler_sha256": "1" * 64,
                }
                for lane in ("native-source-O0", "native-source-O2")
            ],
            "targeted_consumer": {
                "case_id": "sink-write-string-default-bridges",
                "summary_sha256": "2" * 64,
                "compiler_sha256": "3" * 64,
                "lanes": consumer_lanes,
            },
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

    def test_reference_observation_records_partial_evidence_without_promoting(self):
        for is_char_sequence in (False, True):
            with self.subTest(is_char_sequence=is_char_sequence):
                row, observation = self._sink_write_string_observation(is_char_sequence)
                applied = self._apply([], row, [observation], schema_version=2, upstream=self.generator.UPSTREAM)
                self.assertEqual(applied["status"], "unverified")

    def test_reference_observation_rejects_wrong_pin_or_incomplete_native_receipt(self):
        row, valid = self._sink_write_string_observation()
        wrong_candidate = copy.deepcopy(valid)
        wrong_candidate["candidate_sha"] = "a" * 40
        missing_native_case = copy.deepcopy(valid)
        missing_native_case["native_assertion_runs"][0]["execution_ids"].pop()
        wrong_artifact = copy.deepcopy(valid)
        wrong_artifact["reference_abi_probe"]["artifact_coordinate"] = "other:artifact:1"
        for observation in (wrong_candidate, missing_native_case, wrong_artifact):
            with self.subTest(observation=observation):
                with self.assertRaises(SystemExit):
                    self._apply([], row, [observation], schema_version=2, upstream=self.generator.UPSTREAM)

    def test_reference_observation_is_invalidated_when_local_source_changes(self):
        row, observation = self._sink_write_string_observation()
        source = self.repository / "Sources/CompilerCore/Stdlib/kotlinx/io/Utf8.kt"
        source.write_text(source.read_text(encoding="utf-8") + "// changed\n", encoding="utf-8")
        with self.assertRaisesRegex(SystemExit, "stale implementation_input_sha256"):
            self._apply([], row, [observation], schema_version=2, upstream=self.generator.UPSTREAM)

    def test_sink_write_string_bridges_have_exact_declarations_and_direct_test_refs(self):
        expected = {
            (
                "core",
                "kotlinx/io/Utf8Kt",
                "writeString$default",
                "(Lkotlinx/io/Sink;Ljava/lang/String;IIILjava/lang/Object;)V",
            ): {
                "upstream_source": "core/common/src/Utf8.kt:170",
                "local_source": "Sources/CompilerCore/Stdlib/kotlinx/io/Utf8.kt:16",
                "tests": (
                    "core/common/test/AbstractSinkTest.kt#writeUtf8FromIndex",
                    "core/common/test/AbstractSinkTest.kt#writeUtf8WithInvalidIndexes",
                ),
            },
            (
                "core",
                "kotlinx/io/Utf8Kt",
                "writeString$default",
                "(Lkotlinx/io/Sink;Ljava/lang/CharSequence;IIILjava/lang/Object;)V",
            ): {
                "upstream_source": "core/common/src/Utf8.kt:191",
                "local_source": "Sources/CompilerCore/Stdlib/kotlinx/io/Utf8.kt:22",
                "tests": (
                    "core/common/test/AbstractSinkTest.kt#writeCharSequenceFromIndex",
                    "core/common/test/AbstractSinkTest.kt#writeCharSequenceWithInvalidIndexes",
                ),
            },
        }
        expected_local_tests = [
            "Scripts/diff_cases/kotlinx_io_sink_write_string_default_bridges.kt",
            "Scripts/io_api_inventory/run_f02_matrix.py",
            "Scripts/io_api_inventory/probe_sink_write_string_jvm_abi.py",
            "Scripts/kotlinx_io_upstream/run_jvm_reference.py",
            "Scripts/kotlinx_io_upstream/JvmReferenceRunner.java",
            "Scripts/kotlinx_io_upstream/run_candidate_suites.py",
            "Scripts/kotlinx_io_upstream/prepare_candidate_catalog.py",
            "Scripts/kotlinx_io_upstream/fixtures/sink-write-string-default-bridge-source-closure.macos.json",
        ]
        for key, refs in expected.items():
            with self.subTest(key=key):
                row = {
                    "_jvm_key": key,
                    "representation": "JVM public ABI dump",
                    "module": "core",
                    "owner_fqn": "kotlinx/io/Utf8Kt",
                    "_candidate_name": "writeString$default",
                }
                self.assertEqual(self.generator.owner_for(row), "KUU-2634")
                self.assertEqual(self.generator.upstream_test_refs(row, {}), list(refs["tests"]))
                self.assertEqual(self.generator.local_test_refs(row, []), expected_local_tests)
                self.assertEqual(self.generator.validation_obligations(row), ["jvm-descriptor"])
                self.assertEqual(
                    self.generator.SINK_WRITE_STRING_DEFAULT_BRIDGE_SOURCE_REFS[key],
                    (refs["upstream_source"], refs["local_source"]),
                )

        unrelated_row = {
            "_jvm_key": ("core", "kotlinx/io/Utf8Kt", "writeString", "(Lkotlinx/io/Sink;)V"),
            "_candidate_name": "writeString",
            "owner_fqn": "kotlinx/io/Utf8Kt",
            "module": "core",
        }
        self.assertEqual(self.generator.local_test_refs(unrelated_row, []), [])

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
