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
from run_candidate_suites import (compiler_resource_bundle, make_selection_manifest, parse_suite_results,
                                  prepare_suites, select_catalog_rows, validate_full_catalog_artifact)


class CandidateSuitesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.output = self.root / "output"
        self.output.mkdir()
        self.rows = []
        self.lock = {"commit": "fixture", "upstream_files": []}
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
                "upstream_id": source.name + "#original", "upstream_path": source.name,
                "git_blob_sha": blob, "source_set": "common"})

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

    def test_source_function_selection_expands_every_concrete_factory_execution(self):
        first = dict(self.rows[0], upstream_id="core/common/test/AbstractSourceTest.kt#read")
        second = dict(self.rows[1], execution_id="sample.FactoryTest.original",
                      concrete_class="sample.FactoryTest", declaring_class="sample.AbstractSourceTest",
                      upstream_id="core/common/test/AbstractSourceTest.kt#read")
        selected = select_catalog_rows([first, second], None, "linux",
                                        source_function_ids=[first["upstream_id"]])
        self.assertEqual([row["execution_id"] for row in selected],
                         [first["execution_id"], second["execution_id"]])
        with self.assertRaisesRegex(ValueError, "factory-expanded executions"):
            select_catalog_rows([first, second], [first["concrete_class"]], "linux",
                                source_function_ids=[first["upstream_id"]])

    def test_exact_execution_and_invalid_id_selections_are_checked(self):
        exact = self.rows[0]["execution_id"]
        self.assertEqual([row["execution_id"] for row in select_catalog_rows(
            self.rows, None, "linux", execution_ids=[exact])], [exact])
        with self.assertRaisesRegex(ValueError, "unknown concrete execution ID"):
            select_catalog_rows(self.rows, None, "linux", execution_ids=["sample.Missing.test"])
        with self.assertRaisesRegex(ValueError, "unknown source function ID"):
            select_catalog_rows(self.rows, None, "linux", source_function_ids=["missing.kt#missing"])
        with self.assertRaisesRegex(ValueError, "nonempty"):
            select_catalog_rows(self.rows, None, "linux", execution_ids=[""])
        with self.assertRaisesRegex(ValueError, "unique"):
            select_catalog_rows(self.rows, None, "linux", execution_ids=[exact, exact])
        with self.assertRaisesRegex(ValueError, "unique"):
            select_catalog_rows(self.rows, None, "linux",
                                source_function_ids=[self.rows[0]["upstream_id"]] * 2)
        with self.assertRaisesRegex(ValueError, "selected by multiple IDs"):
            select_catalog_rows(self.rows, None, "linux",
                                source_function_ids=[self.rows[0]["upstream_id"]], execution_ids=[exact])
        with self.assertRaisesRegex(ValueError, "at most 10"):
            select_catalog_rows(self.rows, None, "linux", execution_ids=[exact] * 11)

    def test_full_catalog_validation_rejects_a_limited_candidate_artifact(self):
        selected = [self.rows[0]]
        manifest = make_selection_manifest(self.rows, selected, "linux", "explicit-ids", [],
                                            [selected[0]["execution_id"]], "catalog-sha")
        results = [{"execution_id": selected[0]["execution_id"], "status": "PASS"}]
        manifest_path = self.root / "selection.json"
        results_path = self.root / "results.json"
        manifest_path.write_text(json.dumps(manifest))
        results_path.write_text(json.dumps(results))
        with self.assertRaises(ValueError) as raised:
            validate_full_catalog_artifact(json.loads(manifest_path.read_text()),
                                           json.loads(results_path.read_text()),
                                           [row["execution_id"] for row in self.rows])
        self.assertIn("selected execution count mismatch", str(raised.exception))
        self.assertIn("selected execution IDs do not match full catalog", str(raised.exception))
        self.assertIn("result execution IDs do not match full catalog", str(raised.exception))

    def test_full_catalog_validation_accepts_exact_ids_and_all_pass_results(self):
        selected = select_catalog_rows(self.rows, None, "linux")
        manifest = make_selection_manifest(selected, selected, "linux", "full-target-catalog", [], [], "catalog-sha")
        results = [{"execution_id": row["execution_id"], "status": "PASS"} for row in selected]
        validate_full_catalog_artifact(manifest, results, [row["execution_id"] for row in selected])

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

    def run_library_lane(self, library_exit, selector=None, test_library=True,
                         stdlib_from_source=False, optimization="O0"):
        compiler = self.root / "kswiftc"
        compiler.write_bytes(b"compiler")
        if stdlib_from_source:
            source_stdlib = self.root / "KSwiftK_CompilerCore.resources" / "Stdlib"
            source_stdlib.mkdir(parents=True)
            (source_stdlib / "stdlib.kt").write_text("package kotlin\n")
            stdlib_args = ["--stdlib-from-source"]
        else:
            stdlib = self.root / "stdlib"
            stdlib.mkdir()
            (stdlib / "manifest.json").write_text("{}")
            stdlib_args = ["--stdlib-library", str(stdlib)]
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

        def prepare(*arguments, **keywords):
            ports = prepare_suites(*arguments, **keywords)
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
                "--package-root", str(self.root), *stdlib_args,
                "--optimization", optimization, "--output", str(output)]
        if test_library:
            args.append("--test-library")
        if selector:
            args.extend(selector)
        else:
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
        selected_id = self.rows[0]["execution_id"]
        exitcode, stages, summary, results = self.run_library_lane(
            0, selector=["--execution-id", selected_id], optimization="O2")
        self.assertEqual(exitcode, 0)
        self.assertEqual([stage for stage, _ in stages], ["library-compile", "compile", "run"])
        consumer = stages[1][1]
        self.assertIn("-I", consumer)
        self.assertFalse(any(Path(argument).name in {"FirstTest.kt", "SecondTest.kt"} for argument in consumer))
        self.assertIn("-O2", stages[0][1])
        self.assertEqual(summary["counts"], {"PASS": 1})
        self.assertEqual(summary["paired_pass_count"], 0)
        self.assertEqual([row["execution_id"] for row in results], [selected_id])
        self.assertEqual(summary["selected_execution_count"], 1)
        self.assertTrue((self.root / "lane" / "selection.json").is_file())
        self.assertTrue(results[0]["source_sha256"])
        self.assertTrue(results[0]["candidate_port_sha256"])
        selection = json.loads((self.root / "lane" / "selection.json").read_text())
        self.assertEqual(selection["upstream_commit"], "fixture")
        self.assertEqual(selection["selected_execution_records"][0]["source_sha256"], results[0]["source_sha256"])

    def test_source_mode_accepts_source_function_selection(self):
        selected_function = self.rows[0]["upstream_id"]
        exitcode, stages, summary, results = self.run_library_lane(
            0, selector=["--source-function-id", selected_function],
            test_library=False, stdlib_from_source=True, optimization="O0")
        self.assertEqual(exitcode, 0)
        self.assertEqual([stage for stage, _ in stages], ["compile", "run"])
        self.assertIn("--stdlib-from-source", stages[0][1])
        self.assertEqual([row["execution_id"] for row in results], [self.rows[0]["execution_id"]])
        self.assertEqual(summary["selected_source_function_count"], 1)


if __name__ == "__main__":
    unittest.main()
