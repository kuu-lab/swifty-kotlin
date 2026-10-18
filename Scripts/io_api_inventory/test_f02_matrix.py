#!/usr/bin/env python3
"""Guard the F02 gate against reduced scope, skipped defaults and stale artifacts."""
import csv
import json
import contextlib
import io
import struct
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

import generate as inventory_generator
import generate_f02_consumers as generator
import run_f02_matrix as matrix


FAKE_COMPILER = '''#!/usr/bin/env python3
import pathlib,sys
args=sys.argv[1:]
output=pathlib.Path(args[args.index('-o')+1])
if '--emit' in args:
    output.mkdir()
    (output/'objects').mkdir()
    (output/'metadata.bin').write_text('function')
    (output/'manifest.json').write_text('{}')
    (output/'objects/probe.o').write_bytes(b'object')
else:
    assert not any(pathlib.Path(a).name.startswith(('P000_', 'G', 'Fixture')) for a in args if a.endswith('.kt'))
    output.write_text('#!/bin/sh\\nprintf "value:7\\\\n"\\n')
    output.chmod(0o755)
'''


class F02GateTests(unittest.TestCase):
    def test_segment_data_as_byte_array_is_an_independently_selectable_jvm_paired_case(self):
        cases = {case["id"]: case for case in matrix.scenarios()}
        case = cases["segment-data-as-byte-array"]
        self.assertEqual(case["fixture"], matrix.ROOT / "Scripts/io_api_inventory/probes/segment_data_as_byte_array.kt")
        self.assertEqual(case["negative_fixture"], matrix.ROOT / "Scripts/io_api_inventory/probes/segment_data_as_byte_array_negative.kt")
        self.assertEqual(case["reference_probe"], matrix.ROOT / "Scripts/io_api_inventory/probes/segment_data_as_byte_array_jvm_abi.kt")
        self.assertEqual(case["reference"], "jvm")
        self.assertEqual(case["entry"], "f02consumer.main")
        self.assertEqual(case["reference_class"], "f02jvmabi.SegmentDataAsByteArrayJvmAbi")
        abi_probe = case["reference_probe"].read_text(encoding="utf-8")
        self.assertIn("!Modifier.isStatic(method.modifiers)", abi_probe)

    def test_segment_data_as_byte_array_retains_published_api_and_jvm_synthetic(self):
        paths = (
            matrix.ROOT / "Sources/CompilerCore/Stdlib/kotlinx/io/Segment.kt",
            matrix.ROOT / "Scripts/io_api_inventory/upstream/kotlinx-io-0.9.1/core/common/src/Segment.kt",
        )
        for path in paths:
            source = path.read_text(encoding="utf-8")
            match = re.search(
                r"(?P<annotations>(?:^[ \t]*@[^\n]*\n)+)^[ \t]*internal fun dataAsByteArray\(",
                source,
                re.MULTILINE,
            )
            self.assertIsNotNone(match, str(path))
            annotations = {
                name.rsplit(".", 1)[-1]
                for name in re.findall(r"^[ \t]*@([\w.]+)", match.group("annotations"), re.MULTILINE)
            }
            self.assertTrue({"PublishedApi", "JvmSynthetic"}.issubset(annotations), str(path))

    def test_local_probe_evidence_ids_and_candidate_source_metadata_are_explicit(self):
        case_id = "local:Scripts/io_api_inventory/probes/segment_data_as_byte_array.kt#internal-view"
        lane = "source-O0"
        candidate_sha = "a" * 40
        reference_commit = "b" * 40
        reference = matrix.local_probe_execution(
            case_id, lane, candidate_sha, reference_commit, "reference", "PASS"
        )
        candidate = matrix.local_probe_execution(
            case_id, lane, candidate_sha, reference_commit, "candidate", "PASS"
        )
        self.assertEqual(reference["method"], "jvm-probe")
        self.assertEqual(candidate["method"], "native-matrix")
        self.assertNotEqual(reference["execution_id"], candidate["execution_id"])
        self.assertEqual(
            reference["execution_id"],
            matrix.local_probe_execution_id(candidate_sha, reference_commit, case_id, lane, "reference"),
        )
        metadata = matrix.verify_segment_data_as_byte_array_source_metadata()
        self.assertEqual(metadata["status"], "PASS")
        self.assertTrue({"PublishedApi", "JvmSynthetic"}.issubset(metadata["annotations"]))

    def test_visibility_probe_result_is_independent_of_later_lane_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "candidate.json").write_text(
                json.dumps({"status": "EXITED", "exitcode": 1}), encoding="utf-8"
            )
            (directory / "candidate.stderr").write_text(
                "error KSWIFTK-SEMA-0044: Cannot access 'dataAsByteArray': it is internal\n",
                encoding="utf-8",
            )
            self.assertTrue(matrix.visibility_rejection_passed(directory, "candidate"))

            (directory / "candidate.json").write_text(
                json.dumps({"status": "EXITED", "exitcode": 0}), encoding="utf-8"
            )
            self.assertFalse(matrix.visibility_rejection_passed(directory, "candidate"))

            (directory / "candidate.json").write_text(
                json.dumps({"status": "TIMEOUT", "exitcode": 1}), encoding="utf-8"
            )
            self.assertFalse(matrix.visibility_rejection_passed(directory, "candidate"))

    def test_segment_read_context_probe_is_a_dedicated_friend_consumer(self):
        case = next(case for case in matrix.scenarios() if case["id"] == "segment-read-context-impl")
        producer = case["producer"][0].read_text(encoding="utf-8")
        probe = case["jvm_abi_probe"].read_text(encoding="utf-8")

        self.assertEqual(case["entry"], "kuu2590consumer.main")
        self.assertTrue(case["friend_io_artifacts"])
        self.assertEqual(matrix.reference_friend_args(case, [Path("core.jar"), Path("bytestring.jar")]),
                         ["-Xfriend-paths=core.jar,bytestring.jar"])
        self.assertIn("val first: SegmentReadContext = SegmentReadContextImpl", producer)
        self.assertIn("val second: SegmentReadContext = SegmentReadContextImpl", producer)
        self.assertIn("first.getUnchecked(segment, offset + index)", producer)
        self.assertIn("getter.isSynthetic()", probe)
        self.assertIn("getter.invoke(null)", probe)

    def test_generated_public_rows_and_every_full_default_call_are_required(self):
        generated = generator.generate()
        manifest = json.loads(generated["manifest.json"])
        self.assertEqual(len(manifest["paired_source_rows"]), 235)
        self.assertEqual(len(manifest["required_call_ids"]), 275)
        self.assertEqual(len(set(manifest["required_call_ids"])), len(manifest["required_call_ids"]))
        for identifier in manifest["paired_source_rows"]:
            self.assertIn(f'BEGIN:{identifier}', generated["Consumer.kt"])
        for identifier in manifest["required_call_ids"]:
            self.assertIn(f'CALL:{identifier}', generated["Producer.kt"])
            self.assertIn(f'CALL-END:{identifier}', generated["Producer.kt"])
        self.assertIn("import f02ledger.*", generated["Consumer.kt"])
        self.assertNotIn("private fun run_klib", generated["Producer.kt"])
        self.assertIn('println("committed:"', generated["Consumer.kt"])
        self.assertEqual(generator.expression("Byte", "b3"), "4.toByte()")

    def test_deprecated_path_consumer_is_independently_selectable_against_jvm(self):
        case = next(case for case in matrix.scenarios() if case["id"] == "deprecated-path-source-sink")
        self.assertEqual(case["reference"], "jvm")
        self.assertEqual(case["fixture"], matrix.ROOT / "Scripts/diff_cases/kotlinx_io_file_legacy_suppressed.kt")
        self.assertEqual(matrix.LANES, [
            ("source", "O0"), ("source", "O2"),
            ("stdlib-library", "O0"), ("stdlib-library", "O2"),
            ("producer-consumer", "O0"), ("producer-consumer", "O2"),
        ])

    def test_deprecated_path_rows_have_no_unrelated_upstream_assertions(self):
        expected = {
            "jvm-23bdc46eecb769ad": (
                "core/common/src/files/Paths.kt:133",
                "core/common/test/files/SmokeFileTest.kt#createAnEmptyFileUsingSink",
            ),
            "jvm-4a6ead57ff31eb51": (
                "core/common/src/files/Paths.kt:115",
                "core/common/test/files/SmokeFileTest.kt#closeFileSourceTwice",
            ),
            "klib-91d3efd901de8c9b": (
                "core/common/src/files/Paths.kt:133",
                "core/common/test/files/SmokeFileTest.kt#closeFileSinkTwice",
            ),
            "klib-ec16724d485f26fc": (
                "core/common/src/files/Paths.kt:115",
                "core/common/test/files/SmokeFileTest.kt#closeFileSourceTwice",
            ),
        }
        with (matrix.HERE / "api-inventory.tsv").open(encoding="utf-8", newline="") as stream:
            rows = {row["row_id"]: row for row in csv.DictReader(stream, delimiter="\t")}
        for row_id, (source_ref, unrelated_case) in expected.items():
            with self.subTest(row_id=row_id):
                row = rows[row_id]
                self.assertEqual(row["upstream_source_refs"], source_ref)
                self.assertEqual(row["upstream_test_refs"], inventory_generator.NO_DIRECT_UPSTREAM_ASSERTION)
                self.assertEqual(row["status"], "unverified")
                self.assertEqual(
                    inventory_generator.upstream_test_refs(
                        {"upstream_source_refs": source_ref, "_source_paths": []}, {"files": []}
                    ),
                    [],
                )
                self.assertFalse(inventory_generator._case_id_matches_row(row, unrelated_case))
                self.assertIn("Scripts/diff_cases/kotlinx_io_file_legacy_suppressed.kt", row["local_test_refs"])
                self.assertIn("Tests/CompilerCoreTests/Sema/KotlinxIOF01ContractTests.swift", row["local_test_refs"])

    def test_missing_default_call_and_duplicate_row_cannot_pass(self):
        manifest = {"paired_source_rows": ["a"], "required_call_ids": ["a:0", "a:1"]}
        complete = b"BEGIN:a\nCALL:a:0\nCALL-END:a:0\nCALL:a:1\nCALL-END:a:1\nEND:a\n"
        matrix.check_ledger_events(complete, manifest)
        for invalid in (complete.replace(b"CALL:a:1\nCALL-END:a:1\n", b""), complete + b"END:a\n"):
            with self.assertRaises(RuntimeError): matrix.check_ledger_events(invalid, manifest)

    def test_segment_limit_probe_checks_jvm_accessor_descriptors_and_synthetic_flags(self):
        case = next(case for case in matrix.scenarios() if case["id"] == "segment-limit-internal-boundary")
        self.assertTrue(case["fixture"].is_file())
        expected_rows = [
            "internal-11e61a31ae5fe3d2",
            "jvm-92721bc63200d18d",
            "jvm-98dc8444d3a4ea0f",
            "klib-2d963e0c76f5e362",
            "klib-b170c0f57a48a601",
            "klib-c08a0991fed339e4",
        ]
        self.assertEqual(case["row_ids"], expected_rows)
        hashes_by_row = matrix.validation_input_hashes_for_rows(case["row_ids"])
        self.assertEqual(set(hashes_by_row), set(expected_rows))
        self.assertTrue(all(set(hashes) == {"implementation_input_sha256", "test_input_sha256"}
                            for hashes in hashes_by_row.values()))
        output = """\
public final class kotlinx.io.Segment {
  public final int getLimit();
    descriptor: ()I
    flags: (0x1011) ACC_PUBLIC, ACC_FINAL, ACC_SYNTHETIC

  public final void setLimit(int);
    descriptor: (I)V
    flags: (0x1011) ACC_PUBLIC, ACC_FINAL, ACC_SYNTHETIC
}
"""
        result = matrix.check_jvm_abi(output, case["jvm_abi"])
        self.assertEqual([method["descriptor"] for method in result["methods"]], ["()I", "(I)V"])
        with self.assertRaisesRegex(RuntimeError, "descriptor mismatch"):
            matrix.check_jvm_abi(output.replace("descriptor: (I)V", "descriptor: ()V"), case["jvm_abi"])
        with self.assertRaisesRegex(RuntimeError, "ACC_SYNTHETIC"):
            matrix.check_jvm_abi(output.replace("ACC_FINAL, ACC_SYNTHETIC", "ACC_FINAL", 1), case["jvm_abi"])

    def test_segment_limit_candidate_klib_preserves_property_and_accessor_contract(self):
        record = (
            "property symbol fq=kotlinx.io.Segment.limit schema=v1 visibility=internal "
            "sig=I mutable=1 annotations=kotlin.PublishedApi|retention:BINARY;"
            "kotlin.jvm.JvmSynthetic|retention:BINARY|target:get;"
            "kotlin.jvm.JvmSynthetic|retention:BINARY|target:set\n"
        ).encode()
        strings = ["", "kotlinx.io.Segment.limit", "_segment_limit"]
        string_table = b"".join(
            struct.pack("<I", len(value.encode("utf-8"))) + value.encode("utf-8")
            for value in strings
        )

        def metadata_with_record(
            body_record: bytes, *, compact_visibility: int = 2, compact_mutable: bool = True,
        ) -> bytes:
            flags = (1 << 6) if compact_mutable else 0
            entry = struct.pack(
                "<QQIIII12I", 0, len(body_record), 0, flags, 9, compact_visibility,
                1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            )
            return (
                b"kklib-metadata-v3\n"
                + struct.pack("<IIII", 1, len(strings), len(string_table), 80)
                + string_table + entry + body_record
            )

        result = matrix.check_segment_limit_metadata(metadata_with_record(record))
        self.assertEqual(result["visibility"], "internal")
        self.assertEqual(result["signature"], "Int")
        self.assertTrue(result["mutable"])
        self.assertIsNone(result["getter_link"])
        self.assertIsNone(result["setter_link"])
        self.assertEqual(result["accessor_link_mode"], "property-backed")
        self.assertEqual(result["compact_index"]["visibility"], "internal")
        self.assertTrue(result["compact_index"]["mutable"])
        self.assertTrue(result["property_record_sha256"])

        with self.assertRaisesRegex(RuntimeError, "property is not internal"):
            matrix.check_segment_limit_metadata(
                metadata_with_record(record.replace(b"visibility=internal", b"visibility=public"))
            )
        with self.assertRaisesRegex(RuntimeError, "annotations mismatch"):
            matrix.check_segment_limit_metadata(
                metadata_with_record(record.replace(b"target:set", b"target:field"))
            )
        with self.assertRaisesRegex(RuntimeError, "Int signature mismatch"):
            matrix.check_segment_limit_metadata(metadata_with_record(record.replace(b"sig=I", b"sig=J")))
        with self.assertRaisesRegex(RuntimeError, "property is not mutable"):
            matrix.check_segment_limit_metadata(metadata_with_record(record.replace(b"mutable=1 ", b"")))
        with self.assertRaisesRegex(RuntimeError, "compact-index visibility is not internal"):
            matrix.check_segment_limit_metadata(metadata_with_record(record, compact_visibility=0))
        with self.assertRaisesRegex(RuntimeError, "compact-index property is not mutable"):
            matrix.check_segment_limit_metadata(metadata_with_record(record, compact_mutable=False))

        legacy_record = (
            "property symbol fq=kotlinx.io.Segment.limit schema=v1 visibility=internal sig=I "
            "getterLink=kk_segment_limit_get setterLink=kk_segment_limit_set mutable=1 "
            "annotations=kotlin.PublishedApi|retention:BINARY;"
            "kotlin.jvm.JvmSynthetic|retention:BINARY|target:get;"
            "kotlin.jvm.JvmSynthetic|retention:BINARY|target:set\n"
        ).encode()
        legacy_result = matrix.check_segment_limit_metadata(b"kklib-metadata-v2\nbody\n" + legacy_record)
        self.assertEqual(legacy_result["getter_link"], "kk_segment_limit_get")
        self.assertEqual(legacy_result["setter_link"], "kk_segment_limit_set")
        self.assertEqual(legacy_result["accessor_link_mode"], "explicit")

    def test_only_owned_path_prefixes_are_normalized(self):
        work = Path("/private/tmp/f02/lane/run-work")
        with patch.object(matrix.tempfile, "gettempdir", return_value="/var/f02-apple-temp"):
            value = (b"Path:/private/tmp/f02/lane/run-work/tmp/file\n"
                     + b"Path:/var/f02-apple-temp/fixture\n"
                     + b"Path:/tmp/unrelated/file\n")
            expected = b"Path:<tmp>/file\nPath:<tmp>/fixture\nPath:/tmp/unrelated/file\n"
            self.assertEqual(matrix.normalized_paths(value, work), expected)
        with patch.object(matrix.tempfile, "gettempdir", return_value="/tmp"):
            value = b"Path:/tmp/fixture\nPath:/tmp/unrelated/file\n"
            self.assertEqual(matrix.normalized_paths(value, work), value)

    def test_batch_ledger_checks_do_not_consume_other_fixture_protocols(self):
        manifest = {"paired_source_rows": ["a"], "required_call_ids": ["a:0"]}
        ledger = b"BEGIN:a\nCALL:a:0\nCALL-END:a:0\nEND:a\n"
        batch = b"BEGIN-CASE:ledger-jvm\n" + ledger + b"END-CASE:ledger-jvm\n"
        other = b"BEGIN-CASE:numeric\nBEGIN:eof\nEND:eof\nEND-CASE:numeric\n"
        selected = matrix.batch_group_stdout(batch + other, "ledger-jvm")
        self.assertEqual(selected, ledger)
        matrix.check_ledger_events(selected, manifest)
        for invalid in (batch + batch, batch.replace(b"END-CASE:ledger-jvm\n", b""),
                        b"END-CASE:ledger-jvm\nBEGIN-CASE:ledger-jvm\n"):
            with self.assertRaises(RuntimeError): matrix.batch_group_stdout(invalid, "ledger-jvm")
        with self.assertRaises(RuntimeError):
            matrix.check_ledger_events(matrix.batch_group_stdout(batch.replace(b"CALL:a:0\n", b""), "ledger-jvm"), manifest)

    def test_identical_unhandled_reference_and_candidate_outputs_cannot_pass(self):
        for marker in (b"UNHANDLED-FIXTURE:original:IOException:failure\n",
                       b"UNHANDLED-CASE:apple-public:IOException:failure\n"):
            matrix.reject_unhandled_events(b"value:String:UNHANDLED-FIXTURE:is a value\n")
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                compiler = root / "compiler"
                compiler.write_text(FAKE_COMPILER.replace('value:7', marker.decode().strip()))
                compiler.chmod(0o755)
                stdlib = root / "stdlib"
                stdlib.mkdir()
                (stdlib / "manifest.json").write_text("{}")
                consumer = root / "Consumer.kt"
                consumer.write_text("fun main() {}")
                case = {"id": "probe", "producer": [], "consumer": consumer, "reference": "test"}
                for expected in (marker, b"value:7\n"):
                    lane = root / ("same" if expected == marker else "candidate-only")
                    with self.assertRaisesRegex(RuntimeError, "incomplete fixture execution"):
                        matrix.run_lane(case, compiler, stdlib, expected, lane, "source", "O0", 5)
                    self.assertEqual((lane / "run.stdout").read_bytes(), marker)
                with self.assertRaisesRegex(RuntimeError, "incomplete fixture execution"):
                    matrix.reject_unhandled_events(marker)

    def test_package_insertion_preserves_multiline_annotations_and_original_body(self):
        raw = b'@file:OptIn(\n UnsafeIoApi::class\n)\nimport kotlinx.io.*\nfun main() {}\n'
        self.assertEqual(matrix.packaged(raw, "fixture").replace(b"package fixture\n", b""), raw)
        with self.assertRaises(ValueError): matrix.packaged(b"package original\n" + raw, "fixture")

    def test_fixture_driver_records_unhandled_failure_and_keeps_original_bodies(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fixture = root / "original.kt"
            raw = b'import kotlinx.io.Buffer\nfun main() { error("failure") }\n'
            fixture.write_bytes(raw)
            lane = root / "lane"
            lane.mkdir()
            producers, consumer = matrix.prepare({"fixtures": [fixture]}, lane)
            self.assertEqual(producers[0].read_bytes().replace(b"package f02fixture0\n", b""), raw)
            driver = consumer.read_text()
            self.assertIn('UNHANDLED-FIXTURE:original:', driver)
            self.assertIn('catch (failure: Throwable)', driver)
            self.assertLess(driver.index('UNHANDLED-FIXTURE:original:'), driver.index('END-FIXTURE:original'))

    def test_real_processes_retain_only_artifact_and_consumer_inputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            compiler = root / "compiler"
            compiler.write_text(FAKE_COMPILER)
            compiler.chmod(0o755)
            stdlib = root / "stdlib"
            stdlib.mkdir()
            (stdlib / "manifest.json").write_text("{}")
            producer = root / "Producer.kt"
            producer.write_text("package producer\nfun value() = 7\n")
            consumer = root / "Consumer.kt"
            consumer.write_text("fun main() { println(producer.value()) }\n")
            case = {"id": "probe", "producer": [producer], "consumer": consumer, "reference": "test"}
            lane = root / "lane"
            result = matrix.run_lane(case, compiler, stdlib, b"value:7\n", lane, "producer-consumer", "O0", 5)
            self.assertEqual(result["status"], "PASS")
            receipts = [json.loads((lane / f"{stage}.json").read_text()) for stage in ("producer", "consumer")]
            self.assertNotEqual(receipts[0]["pid"], receipts[1]["pid"])
            self.assertNotEqual(receipts[0]["environment"]["KSWIFTK_STDLIB_CACHE_DIR"], receipts[1]["environment"]["KSWIFTK_STDLIB_CACHE_DIR"])
            self.assertFalse((lane / "inputs/P000_Producer.kt").exists())
            self.assertTrue((lane / "inputs/P000_Producer.kt.evidence").is_file())
            with self.assertRaises(RuntimeError):
                matrix.run_lane(case, compiler, stdlib, b"wrong\n", root / "wrong", "producer-consumer", "O0", 5)
            self.assertTrue((root / "wrong/run.stdout").is_file())

    def test_batch_consumers_still_compile_against_typed_producer_exports(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            compiler = root / "compiler"
            compiler.write_text(FAKE_COMPILER)
            compiler.chmod(0o755)
            stdlib = root / "stdlib"
            stdlib.mkdir()
            (stdlib / "manifest.json").write_text("{}")
            producer = root / "P.kt"
            producer.write_text("package producer\nfun value() = 7\n")
            consumer = root / "C.kt"
            consumer.write_text("package consumer\nfun main() { println(producer.value()) }\n")
            part = {"id": "typed", "producer": [producer], "consumer": consumer,
                    "entry": "consumer.main", "reference": "test"}
            case = {"id": "batch", "groups": [part], "entry": "f02allconsumer.main", "reference": "test"}
            lane = root / "lane"
            matrix.run_lane(case, compiler, stdlib, b"value:7\n", lane, "producer-consumer", "O2", 5)
            argv = json.loads((lane / "consumer.json").read_text())["command"]
            self.assertIn(str(lane / "inputs/consumers/C000.kt"), argv)
            self.assertNotIn(str(lane / "inputs/G000P000.kt"), argv)
            self.assertTrue((lane / "inputs/G000P000.kt.evidence").exists())

    def test_failed_lane_does_not_suppress_other_routes_or_apple_originals(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            compiler = root / "compiler"
            compiler.write_text("unused test compiler")
            harness = root / "run_f02_matrix.py"
            harness.write_text("test orchestration provenance")
            (root / "KSwiftK_CompilerCore.bundle/Stdlib").mkdir(parents=True)
            java = root / "java"
            java.write_text('#!/bin/sh\nprintf \'java version "21.0.1"\\n\' >&2\n')
            java.chmod(0o755)
            stdlib = root / "stdlib"
            stdlib.mkdir()
            (stdlib / "manifest.json").write_text(json.dumps({
                "moduleName": "KSwiftKStdlib",
                "kotlinLanguageVersion": matrix.CANDIDATE_KOTLIN_LANGUAGE_VERSION,
            }))
            locks = root / "Scripts/kotlinx_io_upstream"
            locks.mkdir(parents=True)
            (locks / "reference-lock.json").write_text(json.dumps({"sdk_files": [], "jvm_artifacts": []}))
            producer, consumer, expected = [root / name for name in ("P.kt", "C.kt", "expected")]
            producer.write_text("fun value() = 1")
            consumer.write_text("fun main() {}")
            expected.write_bytes(b"value:1\n")
            cases = [{"id": identifier, "producer": [producer], "consumer": consumer,
                      "expected": expected, "reference": "test"}
                     for identifier in ("ordinary", "apple-original25")]
            attempted = []

            def attempt(case, compiler, stdlib, expected, directory, route, optimization, timeout):
                attempted.append((case["id"], route, optimization))
                if len(attempted) == 1:
                    raise RuntimeError("first lane failed")
                return {"status": "PASS", "route": route, "optimization": optimization}

            def git_output(*args, **kwargs):
                return "test-head" if kwargs.get("text") else b"test-patch"

            output = root / "receipts"
            with patch.object(matrix, "ROOT", root), patch.object(matrix, "HERE", root), \
                 patch.object(matrix, "__file__", str(harness)), \
                 patch.object(matrix, "scenarios", return_value=cases), \
                 patch.object(matrix, "generate", return_value={}), \
                 patch.object(matrix, "run_lane", side_effect=attempt), \
                 patch.object(matrix.subprocess, "check_output", side_effect=git_output), \
                 contextlib.redirect_stdout(io.StringIO()):
                exitcode = matrix.main([
                    "--compiler", str(compiler), "--stdlib-library", str(stdlib),
                    "--output", str(output), "--kotlin-home", str(root),
                    "--java", str(java), "--dependencies", str(root),
                ])
            summary = json.loads((output / "summary.json").read_text())
            self.assertEqual(exitcode, 1)
            self.assertEqual(attempted, [(case, route, level)
                for case in ("all-selected", "apple-original25") for route, level in matrix.LANES])
            self.assertEqual(summary["status"], "FAILED_OR_INCOMPLETE")
            self.assertFalse(summary["issue_complete"])
            self.assertEqual(summary["results"][0]["error"], "first lane failed")
            self.assertEqual(sum(result["status"] == "PASS" for result in summary["results"]), 11)


if __name__ == "__main__":
    unittest.main()
