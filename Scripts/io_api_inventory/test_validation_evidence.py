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
        self._write(
            "Scripts/io_api_inventory/bytestring_backing_array/probe-manifest.json",
            json.dumps({"schema_version": 1, "probes": []}),
        )
        self._write(
            "Scripts/io_api_inventory/bytestring_backing_array/execution-catalog.json",
            json.dumps({"schema_version": 1, "executions": []}),
        )
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

    def _apply(self, records, row=None, execution_catalogs=None, probe_execution_records=None):
        fixture_row = copy.deepcopy(row or self.row)
        self.evidence_path.write_text(json.dumps({"schema_version": 1, "records": records}), encoding="utf-8")
        self.generator.apply_validation_evidence(
            [fixture_row], self.lock, self.evidence_path, self.repository, self.upstream,
            execution_catalogs or self._execution_catalogs(),
            probe_execution_records,
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

    def test_only_the_backing_array_internal_and_klib_views_require_apple_reference_lanes(self):
        internal_row = copy.deepcopy(self.row)
        internal_row["row_id"] = "internal-b45a777a1eaf039c"
        klib_row = copy.deepcopy(self.row)
        klib_row["row_id"] = "klib-28163803c351e2f6"
        jvm_row = copy.deepcopy(self.row)
        jvm_row["row_id"] = "jvm-f72f86a64f90dc84"
        required_apple_lanes = ["apple-native-O0", "apple-native-O2"]
        for row in (internal_row, klib_row):
            self.assertIn("apple-native-reference", self.generator.validation_obligations(row))
            self.assertEqual(
                self.generator.required_execution_lanes(self.generator.validation_obligations(row))[-2:],
                required_apple_lanes,
            )
        self.assertNotIn("apple-native-reference", self.generator.validation_obligations(jvm_row))

    def test_backing_array_probe_refs_are_scoped_to_manifest_rows(self):
        probe_path = "Scripts/io_api_inventory/bytestring_backing_array/Probe.kt"
        local_tests = [(probe_path, "package kotlinx.io.bytestring.probe\n")]
        target = {
            "row_id": "internal-b45a777a1eaf039c",
            "_candidate_name": "getBackingArrayReference",
            "owner_fqn": "kotlinx.io.bytestring/ByteString",
        }
        unrelated = {**target, "row_id": "internal-other-bytestring-row"}
        self.assertIn(probe_path, self.generator.local_test_refs(target, local_tests))
        self.assertNotIn(probe_path, self.generator.local_test_refs(unrelated, local_tests))

    def test_registered_local_probe_and_execution_receipts_can_cover_suite_only_upstream_mapping(self):
        case_id = "Scripts/io_api_inventory/bytestring_backing_array/Probe.kt#directIdentity"
        case_path = "Scripts/io_api_inventory/bytestring_backing_array/Probe.kt"
        manifest_path = "Scripts/io_api_inventory/bytestring_backing_array/probe-manifest.json"
        receipt_path = "Scripts/io_api_inventory/bytestring_backing_array/execution-catalog.json"
        self._write(case_path, "package fixture\nfun directIdentity(value: ByteString) = value.getBackingArrayReference()\n")
        self._write("Scripts/io_api_inventory/bytestring_backing_array/Producer.kt", "fun producer() = 1\n")
        self._write("Scripts/io_api_inventory/bytestring_backing_array/Consumer.kt", "fun consumer() = 1\n")
        probe = {
            "case_id": case_id,
            "row_ids": [self.row["row_id"]],
            "input_refs": [
                case_path,
                "Scripts/io_api_inventory/bytestring_backing_array/Producer.kt",
                "Scripts/io_api_inventory/bytestring_backing_array/Consumer.kt",
            ],
            "receipt_ref": receipt_path,
        }
        self._write(manifest_path, json.dumps({"schema_version": 1, "probes": [probe]}))
        row = copy.deepcopy(self.row)
        row["upstream_test_refs"] = "core/common/test/FooTest.kt#suite-reference"
        row["local_test_refs"] += f";{case_path};{manifest_path};{receipt_path}"
        lanes = self.generator.required_execution_lanes(self.generator.validation_obligations(row))
        local_records = []
        receipt_records = []
        catalog = {"reference": {}, "candidate": {}}
        for lane in lanes:
            reference_id = f"probe-reference-{lane}"
            candidate_id = f"probe-candidate-{lane}"
            for side, execution_id in (("reference", reference_id), ("candidate", candidate_id)):
                local_records.append({
                    "execution_id": execution_id,
                    "case_id": case_id,
                    "lane": lane,
                    "side": side,
                    "result": "PASS",
                    "exit_code": 0,
                    "stdout_sha256": "1" * 64,
                    "stderr_sha256": "2" * 64,
                })
                catalog[side][execution_id] = case_id
            receipt_records.extend(local_records[-2:])
        self._write(receipt_path, json.dumps({"schema_version": 1, "executions": receipt_records}))
        executions = [{
            "case_id": case_id,
            "lane": lane,
            "reference": {"execution_id": f"probe-reference-{lane}", "result": "PASS", "exit_code": 0},
            "candidate": {"execution_id": f"probe-candidate-{lane}", "result": "PASS", "exit_code": 0},
        } for lane in lanes]
        record = {
            "row_id": row["row_id"],
            "candidate_sha": "b" * 40,
            "reference_version": self.lock["tag"],
            "reference_commit": self.lock["commit"],
            **self.generator.validation_input_hashes(row, self.repository, self.upstream),
            "compatibility_obligations": self.generator.validation_obligations(row),
            "executions": executions,
        }
        self.assertEqual(self._apply([record], row, catalog)["status"], "verified")

    def test_local_probe_receipt_must_match_evidence_lane_and_side(self):
        case_id = "Scripts/io_api_inventory/bytestring_backing_array/Probe.kt#directIdentity"
        case_path = "Scripts/io_api_inventory/bytestring_backing_array/Probe.kt"
        manifest_path = "Scripts/io_api_inventory/bytestring_backing_array/probe-manifest.json"
        receipt_path = "Scripts/io_api_inventory/bytestring_backing_array/execution-catalog.json"
        self._write(case_path, "fun directIdentity(value: ByteString) = value.getBackingArrayReference()\n")
        self._write("Scripts/io_api_inventory/bytestring_backing_array/Producer.kt", "fun producer() = 1\n")
        self._write("Scripts/io_api_inventory/bytestring_backing_array/Consumer.kt", "fun consumer() = 1\n")
        probe = {
            "case_id": case_id, "row_ids": [self.row["row_id"]],
            "input_refs": [case_path, "Scripts/io_api_inventory/bytestring_backing_array/Producer.kt",
                           "Scripts/io_api_inventory/bytestring_backing_array/Consumer.kt"],
            "receipt_ref": receipt_path,
        }
        self._write(manifest_path, json.dumps({"schema_version": 1, "probes": [probe]}))
        row = copy.deepcopy(self.row)
        row["upstream_test_refs"] = "core/common/test/FooTest.kt#suite-reference"
        row["local_test_refs"] += f";{case_path};{manifest_path};{receipt_path}"
        record = self._record(row)
        for item in record["executions"]:
            item["case_id"] = case_id
            item["reference"]["execution_id"] = f"probe-reference-{item['lane']}"
            item["candidate"]["execution_id"] = f"probe-candidate-{item['lane']}"
        lanes = self.generator.required_execution_lanes(self.generator.validation_obligations(row))
        receipts = []
        catalogs = {"reference": {}, "candidate": {}}
        for lane in lanes:
            for side in ("reference", "candidate"):
                execution_id = f"probe-{side}-{lane}"
                catalogs[side][execution_id] = case_id
                receipts.append({
                    "execution_id": execution_id, "case_id": case_id,
                    "lane": "stdlib-library-O2" if lane == "stdlib-library-O0" else lane,
                    "side": side, "result": "PASS", "exit_code": 0,
                    "stdout_sha256": "1" * 64, "stderr_sha256": "2" * 64,
                })
        self._write(receipt_path, json.dumps({"schema_version": 1, "executions": receipts}))
        record.update(self.generator.validation_input_hashes(row, self.repository, self.upstream))
        with self.assertRaisesRegex(SystemExit, "execution receipt does not match"):
            self._apply([record], row, catalogs)

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
