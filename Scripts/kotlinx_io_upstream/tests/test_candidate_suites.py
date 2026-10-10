import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_candidate_subset import PREFIX
import run_candidate_suites as runner
from run_candidate_suites import compiler_resource_bundle, parse_suite_results, prepare_suites


class CandidateSuitesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.output = self.root / "output"
        self.output.mkdir()
        self.rows = []
        self.lock = {"upstream_files": []}
        self.suites = ["sample.FirstTest", "sample.SecondTest"]
        for suite in self.suites:
            name = suite.split(".")[-1]
            raw = f"package sample\nclass {name} {{ fun original() {{ check(2 + 2 == 4) }} }}\n".encode()
            source = self.root / (name + ".kt")
            source.write_bytes(raw)
            blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
            self.lock["upstream_files"].append({"path": source.name,
                "sha256": hashlib.sha256(raw).hexdigest(), "git_blob_sha": blob})
            self.rows.append({"execution_id": suite + ".original", "concrete_class": suite,
                "declaring_class": suite, "method_name": "original", "parameter_types": "",
                "upstream_path": source.name, "git_blob_sha": blob})

    def prepare(self):
        return prepare_suites(self.root, self.rows, self.lock, self.suites, self.output)

    def events(self, port, result="PASS"):
        identifier = port["execution_ids"][0]
        return f'{port["event_token"]} BEGIN {identifier}\n{port["event_token"]} {result} {identifier}\n'

    def test_each_original_source_and_fresh_constructor_survive_combining(self):
        ports = self.prepare()
        for port in ports:
            self.assertEqual(Path(port["port_path"]).read_bytes(), PREFIX + (self.root / port["source_path"]).read_bytes())
        driver = (self.output / "CombinedDriver.kt").read_text()
        self.assertEqual(driver.count("fun main()"), 1)
        for suite in self.suites:
            self.assertIn(suite + "().original()", driver)
        text = "".join(self.events(port) for port in ports)
        self.assertEqual([row["status"] for row in parse_suite_results(text, ports)], ["PASS", "PASS"])

    def test_missing_and_failed_suite_cannot_be_counted_as_success(self):
        ports = self.prepare()
        rows = parse_suite_results(self.events(ports[0]), ports)
        self.assertEqual([row["status"] for row in rows], ["PASS", "NOT_RUN"])
        rows = parse_suite_results(self.events(ports[0]) + self.events(ports[1], "FAIL"), ports)
        self.assertEqual([row["status"] for row in rows], ["PASS", "FAIL"])

    def test_unfinished_test_is_not_hidden_by_completed_other_suite(self):
        ports = self.prepare()
        unfinished = f'{ports[0]["event_token"]} BEGIN {ports[0]["execution_ids"][0]}\n'
        rows = parse_suite_results(unfinished + self.events(ports[1]), ports)
        self.assertEqual([row["status"] for row in rows], ["NOT_FINISHED", "PASS"])

    def test_duplicate_selection_and_shared_source_need_verified_driver(self):
        with self.assertRaisesRegex(ValueError, "unique"):
            prepare_suites(self.root, self.rows, self.lock, [self.suites[0]] * 2, self.output)
        with self.assertRaisesRegex(ValueError, "nonempty"):
            prepare_suites(self.root, self.rows, self.lock, [], self.output)
        # A second concrete class from the first original file must not compile it twice.
        self.rows[1].update({"upstream_path": self.rows[0]["upstream_path"], "git_blob_sha": self.rows[0]["git_blob_sha"]})
        with self.assertRaisesRegex(ValueError, "share a source file"):
            self.prepare()

    def test_cross_suite_duplicate_execution_id_is_rejected(self):
        ports = self.prepare()
        ports[1] = dict(ports[0])
        with self.assertRaisesRegex(ValueError, "duplicate execution ID"):
            parse_suite_results(self.events(ports[0]), ports)

    def test_resource_bundle_uses_resolved_compiler_sibling(self):
        compiler = self.root / "kswiftc"
        compiler.write_bytes(b"compiler")
        self.assertIsNone(compiler_resource_bundle(compiler, None))
        resources = self.root / "KSwiftK_CompilerCore.resources"
        (resources / "Stdlib").mkdir(parents=True)
        self.assertEqual(compiler_resource_bundle(compiler, None), resources)
        with self.assertRaisesRegex(ValueError, "contain Stdlib"):
            compiler_resource_bundle(compiler, self.root / "missing")

    def test_macos_bundle_uses_contents_resources(self):
        compiler = self.root / "kswiftc"
        compiler.write_bytes(b"compiler")
        bundle = self.root / "KSwiftK_CompilerCore.bundle"
        resources = bundle / "Contents" / "Resources"
        (resources / "Stdlib").mkdir(parents=True)
        self.assertEqual(compiler_resource_bundle(compiler, None), resources)
        self.assertEqual(compiler_resource_bundle(compiler, bundle), resources)

    def run_library_lane(self, library_exit):
        compiler = self.root / "kswiftc"
        compiler.write_bytes(b"compiler")
        stdlib = self.root / "stdlib"
        stdlib.mkdir()
        (stdlib / "manifest.json").write_text("{}")
        for directory in ["Sources/CompilerCore/Stdlib", "Sources/Runtime", "Sources/RuntimeABI"]:
            (self.root / directory).mkdir(parents=True)
            (self.root / directory / "input.txt").write_text("locked input")
        (self.root / "Package.swift").write_text("package")
        (self.root / "run_candidate_subset.py").write_text("helper")
        (self.root / "run_jvm_reference.py").write_text("helper")
        catalog = self.root / "native-executions.expected.json"
        catalog.write_text(json.dumps(self.rows))
        self.lock["native_execution_catalog_sha256"] = hashlib.sha256(catalog.read_bytes()).hexdigest()
        (self.root / "reference-lock.json").write_text(json.dumps(self.lock))
        output = self.root / "lane"
        stages = []
        captured_ports = []

        def prepare(*arguments):
            ports = prepare_suites(*arguments)
            captured_ports.extend(ports)
            return ports

        def execute(command, directory, stage, timeout, environment=None):
            stages.append((stage, command))
            if stage == "library-compile":
                if library_exit == 0:
                    Path(command[-1]).mkdir()
                    (Path(command[-1]) / "manifest.json").write_text("original bodies")
                return library_exit
            if stage == "compile":
                Path(command[-1]).write_bytes(b"consumer")
                return 0
            (directory / "run.stdout").write_text("".join(self.events(port) for port in captured_ports))
            return 0

        args = ["--upstream", str(self.root), "--compiler", str(compiler),
                "--package-root", str(self.root), "--stdlib-library", str(stdlib),
                "--test-library", "--output", str(output)]
        for suite in self.suites:
            args += ["--suite", suite]
        with patch.object(runner, "HERE", self.root), patch.object(runner, "execute", execute), patch.object(runner, "prepare_suites", prepare):
            exitcode = runner.main(args)
        summary = json.loads((output / "summary.json").read_text())
        self.assertNotIn("error", summary, summary)
        return exitcode, stages, summary, json.loads((output / "results.json").read_text())

    def test_library_failure_keeps_all_ids_and_checks_inputs(self):
        exitcode, stages, summary, results = self.run_library_lane(1)
        self.assertEqual(exitcode, 1)
        self.assertEqual([stage for stage, _ in stages], ["library-compile"])
        self.assertEqual(summary["counts"], {"NOT_RUN": 2})
        self.assertTrue(summary["inputs_unchanged"])
        self.assertEqual({row["execution_id"] for row in results}, {row["execution_id"] for row in self.rows})

    def test_consumer_imports_library_without_recompiling_original_bodies(self):
        exitcode, stages, summary, results = self.run_library_lane(0)
        self.assertEqual(exitcode, 0)
        self.assertEqual([stage for stage, _ in stages], ["library-compile", "compile", "run"])
        consumer = stages[1][1]
        self.assertIn("-I", consumer)
        self.assertFalse(any(Path(argument).name in {"FirstTest.kt", "SecondTest.kt"} for argument in consumer))
        self.assertEqual(summary["counts"], {"PASS": 2})
        self.assertEqual(summary["paired_pass_count"], 0)
        self.assertEqual(len(results), 2)


if __name__ == "__main__":
    unittest.main()
