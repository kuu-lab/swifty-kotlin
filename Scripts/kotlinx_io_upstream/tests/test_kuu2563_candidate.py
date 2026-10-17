#!/usr/bin/env python3
"""Guard KUU-2563's locked inherited selection and original assertion extraction."""

import json
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
import run_kuu2563_candidate as runner

API_GENERATOR_PATH = HERE.parent / "io_api_inventory" / "generate.py"
API_GENERATOR_SPEC = importlib.util.spec_from_file_location("kuu2563_api_generator", API_GENERATOR_PATH)
API_GENERATOR = importlib.util.module_from_spec(API_GENERATOR_SPEC)
API_GENERATOR_SPEC.loader.exec_module(API_GENERATOR)


class Kuu2563CandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scope = json.loads(runner.SCOPE_PATH.read_text(encoding="utf-8"))
        cls.lock = json.loads(runner.LOCK_PATH.read_text(encoding="utf-8"))
        cls.catalog = json.loads(runner.CATALOG_PATH.read_text(encoding="utf-8"))

    def test_scope_expands_only_sixty_jvm_executions_and_no_native_ids(self):
        rows = runner.select_rows(self.catalog, self.scope)
        self.assertEqual(len(rows), 60)
        self.assertEqual({row["upstream_id"] for row in rows}, set(self.scope["source_function_ids"]))
        native_ids = {row["upstream_id"] for row in json.loads(runner.NATIVE_CATALOG_PATH.read_text())}
        self.assertFalse(set(self.scope["source_function_ids"]) & native_ids)

    def test_api_rows_link_only_their_exact_original_assertion_functions(self):
        expected = {
            "jvm-2cd93875bc5aede4": {
                "core/jvm/test/AbstractSourceTestJVM.kt#readNioBuffer",
            },
            "jvm-5c8f62b61ce2a00a": {
                "core/jvm/test/AbstractSourceTestJVM.kt#inputStream",
                "core/jvm/test/AbstractSourceTestJVM.kt#inputStreamOffsetCount",
                "core/jvm/test/AbstractSourceTestJVM.kt#inputStreamClosesSource",
            },
        }
        for row_id, direct_refs in expected.items():
            with self.subTest(row_id=row_id):
                row = {"row_id": row_id, "module": "core", "owner_fqn": "kotlinx/io/SourcesJvmKt",
                       "_candidate_name": "readAtMostTo", "upstream_source_refs": "core/jvm/src/SourcesJvm.kt:143",
                       "_source_paths": []}
                self.assertEqual(set(API_GENERATOR.upstream_test_refs(row, {"files": []})), direct_refs)

    def test_function_extractor_balances_lambdas_and_maps_exception_assertion_lines(self):
        source = (
            "class Sample {\n"
            "    fun inputStreamBounds() {\n"
            "        assertFailsWith<IllegalArgumentException> {\n"
            "            input.read(ByteArray(100), 50, 51)\n"
            "        }\n"
            "    }\n"
            "}\n"
        )
        snippet, start_line, end_line = runner.extract_function(source, "inputStreamBounds")
        assertions = runner.assertion_rows(source, "inputStreamBounds", snippet, start_line)
        self.assertEqual((start_line, end_line), (2, 6))
        self.assertEqual(len(assertions), 1)
        self.assertEqual((assertions[0]["line_start"], assertions[0]["line_end"]), (3, 5))
        self.assertEqual(assertions[0]["required_observations"], ["exception_type"])

    def test_observation_parser_rejects_missing_ids_and_keeps_assertions(self):
        identifier = "[engine:junit-jupiter]/[class:kotlinx.io.BufferSourceTestJVM]/[method:inputStream()]"
        text = "\n".join((
            f"{runner.OBSERVATION_TOKEN}\t{identifier}\tBEGIN\tinputStream",
            f"{runner.OBSERVATION_TOKEN}\t{identifier}\tVALUE\t3\t3",
            f"{runner.OBSERVATION_TOKEN}\t{identifier}\tEND\t1\tassertions-executed",
        ))
        result = runner.parse_observations(text, [identifier])
        self.assertEqual(result[identifier]["values"], [{"expected": "3", "actual": "3"}])
        with self.assertRaisesRegex(ValueError, "missing observation"):
            runner.parse_observations("", [identifier])

    def test_candidate_process_classification_keeps_crashes_and_timeouts_distinct(self):
        self.assertEqual(runner.classify_process_result(0, False), "EXITED_ZERO")
        self.assertEqual(runner.classify_process_result(1, False), "NONZERO_EXIT")
        self.assertEqual(runner.classify_process_result(-5, False), "CRASH")
        self.assertEqual(runner.classify_process_result(124, True), "TIMEOUT")

    def test_friend_helper_is_only_added_for_klib_candidate_lanes(self):
        port = Path("OriginalSourceTests.kt")
        factory = Path("SourceFactory.kt")
        probe = Path("ApiContractProbe.kt")
        helper = Path("Kuu2563FriendAccess.kt")
        source_lane = runner.candidate_test_support_sources(port, factory, probe, helper, True)
        klib_lane = runner.candidate_test_support_sources(port, factory, probe, helper, False)
        self.assertEqual(source_lane, [str(port), str(factory), str(probe)])
        self.assertEqual(klib_lane, [str(port), str(factory), str(probe), str(helper)])
        self.assertIn(runner.FRIEND_ACCESS_HELPER_DECLARATION, runner.FRIEND_ACCESS_HELPER_SOURCE)

    def test_friend_helper_matches_the_candidate_stdlib_declaration(self):
        with tempfile.TemporaryDirectory() as temporary:
            package_root = Path(temporary)
            source_path = package_root / "Sources/CompilerCore/Stdlib/kotlinx/io/-Util.kt"
            source_path.parent.mkdir(parents=True)
            source_path.write_text(runner.FRIEND_ACCESS_HELPER_DECLARATION + "\n", encoding="utf-8")
            self.assertEqual(runner.verify_friend_helper_declaration(package_root), runner.sha256(source_path))
            source_path.write_text("internal fun minOf(a: Long, b: Long): Long = b\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "differs from the pinned"):
                runner.verify_friend_helper_declaration(package_root)

    def test_coverage_mapping_records_buffer_guard_as_original_path(self):
        upstream_id = "core/jvm/test/AbstractSourceTestJVM.kt#inputStreamForClosedSource"
        execution_id = "[engine:junit-jupiter]/[class:kotlinx.io.BufferSourceTestJVM]/[method:inputStreamForClosedSource()]"
        scope = {
            "source_function_ids": [upstream_id], "expected_jvm_execution_count": 1,
            "source_path": "core/jvm/test/AbstractSourceTestJVM.kt", "source_sha256": "a" * 64,
            "source_git_blob_sha": "b" * 40,
        }
        generated = {"selected_functions": {upstream_id: [
            {"id": "inputStreamForClosedSource:buffer-early-return", "source_path": scope["source_path"],
             "source_sha256": "a" * 64, "line_start": 1, "line_end": 1,
             "expression": "if (source is kotlinx.io.Buffer) { return }", "required_observations": ["value"],
             "kind": "original conditional path, not a skipped execution"},
            {"id": "inputStreamForClosedSource:assertion-1", "source_path": scope["source_path"],
             "source_sha256": "a" * 64, "line_start": 2, "line_end": 2,
             "expression": "assertFailsWith<IOException> { input.read() }", "required_observations": ["exception_type"]},
        ]}}
        observation = {"value": {"assertions": [], "original_path": "Buffer early return"}}
        entries = runner.build_coverage_entries(
            scope, {}, [{"execution_id": execution_id, "upstream_id": upstream_id, "source_set": "jvm",
                        "concrete_class": "kotlinx.io.BufferSourceTestJVM", "display_name": "inputStreamForClosedSource()",
                        "declaring_class": "kotlinx.io.AbstractSourceTestJVM", "method_name": "inputStreamForClosedSource",
                        "parameter_types": ""}],
            generated, {execution_id: observation}, {execution_id: observation}, {"status": "PASS"},
            "Scripts/kotlinx_io_upstream/evidence/fixture.json", "c" * 64)
        self.assertEqual(entries[0]["executions"][0]["assertion_ids"],
                         ["inputStreamForClosedSource:buffer-early-return"])
        self.assertEqual(entries[0]["executions"][0]["candidate"]["result"]["sha256"], "c" * 64)

    def test_coverage_mapping_rejects_incomplete_matrix_or_observation_difference(self):
        upstream_id = "core/jvm/test/AbstractSourceTestJVM.kt#readNioBuffer"
        identifier = "jvm.readNioBuffer"
        scope = {"source_function_ids": [upstream_id], "expected_jvm_execution_count": 1,
                 "source_path": "core/jvm/test/AbstractSourceTestJVM.kt", "source_sha256": "a" * 64,
                 "source_git_blob_sha": "b" * 40}
        generated = {"selected_functions": {upstream_id: [{"id": "readNioBuffer:assertion-1"}]}}
        row = {"execution_id": identifier, "upstream_id": upstream_id, "source_set": "jvm",
               "concrete_class": "kotlinx.io.PeekBufferTestJVM", "display_name": "readNioBuffer()",
               "declaring_class": "kotlinx.io.AbstractSourceTestJVM", "method_name": "readNioBuffer",
               "parameter_types": ""}
        observation = {"value": {"assertions": []}}
        arguments = (scope, {}, [row], generated, {identifier: observation}, {identifier: observation})
        with self.assertRaisesRegex(ValueError, "incomplete candidate matrix"):
            runner.build_coverage_entries(*arguments, {"status": "FAIL"}, "evidence.json", "c" * 64)
        with self.assertRaisesRegex(ValueError, "observations differ"):
            runner.build_coverage_entries(*arguments[:4], {identifier: observation},
                {identifier: {"value": {"assertions": [{"expected": "7", "actual": "6"}]}}},
                {"status": "PASS"}, "evidence.json", "c" * 64)


if __name__ == "__main__":
    unittest.main()
