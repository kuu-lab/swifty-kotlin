import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_candidate_subset import KUU_2566_METHODS, PREFIX, main, parse_events, prepare_port, tree_hash


class CandidateSubsetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "ExampleTest.kt"
        self.raw = b'package sample\nclass ExampleTest { fun original() { check(2 + 2 == 4) } }\n'
        self.source.write_bytes(self.raw)
        self.blob = hashlib.sha1(b"blob " + str(len(self.raw)).encode() + b"\0" + self.raw).hexdigest()
        self.lock = {"upstream_files": [{"path": self.source.name,
                     "sha256": hashlib.sha256(self.raw).hexdigest(), "git_blob_sha": self.blob}]}
        self.rows = [{"execution_id": "sample.ExampleTest.original", "concrete_class": "sample.ExampleTest",
                      "declaring_class": "sample.ExampleTest", "method_name": "original", "parameter_types": "",
                      "upstream_path": self.source.name, "git_blob_sha": self.blob}]
        self.output = self.root / "output"
        self.output.mkdir()

    def test_port_preserves_assertion_bytes_and_fresh_constructor(self):
        result = prepare_port(self.root, self.rows, self.lock, self.output)
        self.assertEqual(Path(result["port_path"]).read_bytes(), PREFIX + self.raw)
        self.assertEqual(self.source.read_bytes(), self.raw)
        driver = Path(result["driver_path"]).read_text()
        self.assertIn("sample.ExampleTest().original()", driver)
        self.assertFalse(result["assertions_parameters_constructors_changed"])

    def test_jvm_catalog_execution_id_is_preserved_by_native_bridge_driver(self):
        identifier = "[engine:junit-jupiter]/[class:sample.ExampleTest]/[method:original()]"
        row = {**self.rows[0], "execution_id": identifier, "source_set": "jvm"}
        result = prepare_port(self.root, [row], self.lock, self.output)
        self.assertEqual(result["execution_ids"], [identifier])
        self.assertIn(identifier, Path(result["driver_path"]).read_text())
        self.assertIn("sample.ExampleTest().original()", Path(result["driver_path"]).read_text())

    def test_kuu_2566_method_closure_preserves_only_selected_original_methods(self):
        source = self.root / "BufferTest.kt"
        declarations = []
        for method in sorted(KUU_2566_METHODS):
            declarations.append(
                f'    @Test\n    fun {method}() {{\n'
                '        val marker = "}"\n'
                '        if (marker.isNotEmpty()) {\n'
                '            assertEquals("}", marker)\n'
                '        }\n'
                '    }'
            )
        raw = (
            "package kotlinx.io\n\nimport kotlin.test.Test\nimport kotlin.test.assertEquals\n\n"
            "private const val SEGMENT_SIZE = Segment.SIZE\n\nclass BufferTest {\n"
            + "\n".join(declarations)
            + "\n    @Test\n    fun unrelated() { assertEquals(1, 1) }\n}\n"
        ).encode()
        source.write_bytes(raw)
        blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        lock = {"upstream_files": [{"path": source.name,
                "sha256": hashlib.sha256(raw).hexdigest(), "git_blob_sha": blob}]}
        rows = [{
            "execution_id": f"[engine:junit-jupiter]/[class:kotlinx.io.BufferTest]/[method:{method}()]",
            "concrete_class": "kotlinx.io.BufferTest", "declaring_class": "kotlinx.io.BufferTest",
            "method_name": method, "parameter_types": "", "upstream_path": source.name,
            "git_blob_sha": blob,
        } for method in KUU_2566_METHODS]

        result = prepare_port(self.root, rows, lock, self.output, method_source_closure=True)
        port = Path(result["port_path"]).read_text()
        self.assertEqual(result["source_port_mode"], "selected-original-test-method-closure")
        self.assertEqual(len(result["selected_method_source_records"]), 10)
        self.assertTrue(all(row["source_region_preserved_exactly"]
                            for row in result["selected_method_source_records"]))
        self.assertNotIn("fun unrelated()", port)
        self.assertEqual(port.count("    fun "), 10)
        for row in rows:
            self.assertIn(f"    fun {row['method_name']}()", port)

    def test_modified_upstream_is_rejected(self):
        self.source.write_bytes(self.raw.replace(b"== 4", b"== 5"))
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            prepare_port(self.root, self.rows, self.lock, self.output)

    def test_inherited_factory_and_parameters_are_not_silently_lost(self):
        for override in [{"declaring_class": "sample.AbstractTest"}, {"parameter_types": "int"}]:
            with self.subTest(override=override), self.assertRaisesRegex(ValueError, "verified driver"):
                prepare_port(self.root, [{**self.rows[0], **override}], self.lock, self.output)

    def test_lifecycle_hooks_are_rejected(self):
        raw = self.raw + b'@AfterTest\nfun cleanup() {}\n'
        self.source.write_bytes(raw)
        blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        lock = {"upstream_files": [{"path": self.source.name, "sha256": hashlib.sha256(raw).hexdigest(), "git_blob_sha": blob}]}
        with self.assertRaisesRegex(ValueError, "lifecycle driver"):
            prepare_port(self.root, [{**self.rows[0], "git_blob_sha": blob}], lock, self.output)

    def test_failed_and_missing_tests_never_pass(self):
        results = parse_events("TOKEN BEGIN first\nbody output\nTOKEN FAIL first\nTOKEN EXCEPTION kotlin.AssertionError\n",
                               ["first", "second"], "TOKEN")
        self.assertEqual([row["status"] for row in results], ["FAIL", "NOT_RUN"])
        self.assertEqual(results[0]["stdout"], "body output\n")
        self.assertEqual(results[0]["exception_type"], "kotlin.AssertionError")
        unfinished = parse_events("TOKEN BEGIN first\n", ["first"], "TOKEN")
        self.assertEqual(unfinished[0]["status"], "NOT_FINISHED")

    def test_duplicate_unexpected_and_invalid_events_are_rejected(self):
        for text in ["TOKEN BEGIN other\n", "TOKEN PASS first\n",
                     "TOKEN BEGIN first\nTOKEN PASS first\nTOKEN BEGIN first\n",
                     "TOKEN UNKNOWN first\n", "TOKEN EXCEPTION kotlin.AssertionError\n"]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_events(text, ["first"], "TOKEN")

    def test_missing_and_empty_inputs_are_rejected(self):
        for path in [self.root / "missing", self.output]:
            with self.subTest(path=path), self.assertRaises(ValueError):
                tree_hash(path)

    def test_nonfinite_timeouts_are_rejected_before_running_a_compiler(self):
        for index, value in enumerate(["nan", "inf", "0", "-1"]):
            output = self.root / f"invalid-timeout-{index}"
            code = main(["--upstream", str(self.root), "--compiler", str(self.root / "nonexistent"),
                         "--stdlib-library", str(self.root), "--package-root", str(self.root),
                         "--suite", "sample.ExampleTest", "--output", str(output), "--run-timeout", value])
            self.assertEqual(code, 1)
            self.assertIn("finite and positive", json.loads((output / "summary.json").read_text())["error"])
            self.assertFalse((output / "compile.command.json").exists())


if __name__ == "__main__":
    unittest.main()
