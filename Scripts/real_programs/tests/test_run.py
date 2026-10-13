"""Regression checks for false passes in the public-consumer runner."""

import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


RUNNER_PATH = Path(__file__).resolve().parents[1] / "run.py"
SPEC = importlib.util.spec_from_file_location("real_programs_runner", RUNNER_PATH)
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.corpus = self.root / "corpus"
        self.corpus.mkdir()
        self.manifest = {
            "schema_version": 1, "issue": "TEST-1", "reference_kotlin_version": "2.3.10",
            "cases": [self.case("first"), self.case("second")],
        }
        self.save_manifest()
        self.tool = self.root / "tool"
        self.tool.write_text(f"#!{sys.executable}\n" + '''
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ["FAKE_TRACE"], "a") as trace:
    trace.write(json.dumps(args) + "\\n")
if args == ["-version"]:
    print("info: kotlinc-jvm " + os.environ.get("FAKE_VERSION", "2.3.10"))
elif "--stdlib-only" in args:
    target = pathlib.Path(args[args.index("-o") + 1])
    target.mkdir()
    (target / "manifest.json").write_text('{}')
elif "-jar" in args:
    os.execv(sys.executable, [sys.executable, args[-1]])
else:
    if os.environ.get("FAKE_COMPILE_EXIT"):
        sys.exit(int(os.environ["FAKE_COMPILE_EXIT"]))
    flag = "-d" if "-d" in args else "-o"
    target = pathlib.Path(args[args.index(flag) + 1])
    if os.environ.get("FAKE_NO_BINARY"):
        sys.exit(0)
    target.write_text("#!" + sys.executable + "\\n" + """
import os, sys, time
sys.stdout.write(os.environ.get("FAKE_STDOUT", "correct" + chr(10)))
sys.stderr.write(os.environ.get("FAKE_STDERR", ""))
sys.stdout.flush()
sys.stderr.flush()
time.sleep(float(os.environ.get("FAKE_SLEEP", "0")))
sys.exit(int(os.environ.get("FAKE_RUN_EXIT", "0")))
""")
    target.chmod(0o755)
''')
        self.tool.chmod(0o755)
        self.output = self.root / "output"
        self.trace = self.root / "trace.jsonl"

    def record(self, name, filename, data):
        path = self.corpus / name / filename
        path.parent.mkdir(exist_ok=True)
        path.write_bytes(data)
        return {"path": f"{name}/{filename}", "sha256": hashlib.sha256(data).hexdigest()}

    def case(self, name):
        revision = "a" * 40
        source = self.record(name, "Source.kt", b"fun consumer() = 1\n")
        source.update(upstream_path="src/Source.kt", url=f"https://github.com/example/project/blob/{revision}/src/Source.kt")
        return {
            "name": name, "repository": "example/project", "revision": revision,
            "sources": [source], "main": self.record(name, "Main.kt", b"fun main() {}\n"),
            "license": self.record(name, "LICENSE.txt", b"MIT\n"),
            "expected": {"stdout": self.record(name, "expected.stdout", b"correct\n"),
                         "stderr": self.record(name, "expected.stderr", b""), "exit_code": 0},
            "related_issues": [],
        }

    def save_manifest(self):
        (self.corpus / "manifest.json").write_text(json.dumps(self.manifest))

    def run_gate(self, lane="native", extra=(), environment=None):
        arguments = ["--corpus", str(self.corpus), "--output-dir", str(self.output),
                     "--lane", lane, "--kswiftc", str(self.tool), "--kotlinc", str(self.tool),
                     "--java", str(self.tool), *extra]
        with patch.dict(os.environ, {"FAKE_TRACE": str(self.trace), **(environment or {})}):
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                return RUNNER.main(arguments)

    def report(self):
        return json.loads((self.output / "report.json").read_text())

    def test_complete_gate_builds_one_stdlib_for_both_optimizations(self):
        self.assertEqual(self.run_gate(lane="all"), 0)
        report = self.report()
        self.assertTrue(report["complete_verification"])
        self.assertEqual(len(report["results"]), 6)
        calls = [json.loads(line) for line in self.trace.read_text().splitlines()]
        self.assertEqual(sum("--stdlib-only" in call for call in calls), 1)
        consumers = [call for call in calls if "--stdlib-library" in call]
        self.assertEqual(len(consumers), 4)
        self.assertEqual({call[call.index("--stdlib-library") + 1] for call in consumers},
                         {str(self.output / "stdlib.kklib")})
        self.assertEqual(sum("-O0" in call for call in consumers), 2)
        self.assertEqual(sum("-O2" in call for call in consumers), 2)

    def test_selected_case_does_not_claim_complete_verification(self):
        self.assertEqual(self.run_gate(lane="all", extra=["--case", "first"]), 0)
        self.assertFalse(self.report()["complete_verification"])
        self.assertFalse(self.report()["full_corpus"])

    def test_output_and_exit_failures_are_not_passes(self):
        for environment, status in [
            ({"FAKE_STDOUT": "wrong\n"}, "OUTPUT_MISMATCH"),
            ({"FAKE_STDERR": "unexpected exception\n"}, "OUTPUT_MISMATCH"),
            ({"FAKE_RUN_EXIT": "1"}, "RUN_FAIL"),
            ({"FAKE_COMPILE_EXIT": "1"}, "COMPILE_FAIL"),
            ({"FAKE_NO_BINARY": "1"}, "MISSING_EXECUTABLE"),
        ]:
            with self.subTest(status=status, environment=environment):
                self.output = self.root / ("output" + str(len(list(self.root.glob('output*')))))
                self.assertEqual(self.run_gate(environment=environment), 1)
                self.assertEqual({r["status"] for r in self.report()["results"]}, {status})
                self.assertFalse(self.report()["complete_verification"])

    def test_timeout_is_not_success_even_with_matching_partial_output(self):
        self.assertEqual(self.run_gate(extra=["--run-timeout", "0.2"], environment={"FAKE_SLEEP": "3"}), 1)
        self.assertEqual({r["status"] for r in self.report()["results"]}, {"RUN_TIMEOUT"})
        self.assertTrue(all(r["stdout_match"] for r in self.report()["results"]))

    def test_existing_output_is_preserved_and_rejected(self):
        self.output.mkdir()
        previous = self.output / "report.json"
        previous.write_text("previous report")
        self.assertEqual(self.run_gate(), 2)
        self.assertEqual(previous.read_text(), "previous report")
        self.assertFalse(self.trace.exists())

    def test_source_tampering_and_unknown_cases_stop_before_compilation(self):
        self.assertEqual(self.run_gate(extra=["--case", "missing"]), 2)
        (self.corpus / "first/Source.kt").write_text("modified upstream source")
        self.assertEqual(self.run_gate(), 2)
        self.assertFalse(self.trace.exists())

    def test_missing_original_consumer_is_rejected(self):
        self.manifest["issue"] = "KUU-1854"
        self.save_manifest()
        self.assertEqual(self.run_gate(), 2)
        self.assertFalse(self.trace.exists())

    def test_wrong_reference_version_is_rejected(self):
        self.assertEqual(self.run_gate(lane="all", environment={"FAKE_VERSION": "2.4.20"}), 2)
        self.assertEqual(self.report()["results"], [])
        self.assertFalse(self.report()["complete_verification"])

    def test_source_mode_runs_both_optimizations_without_a_library(self):
        self.assertEqual(self.run_gate(extra=["--stdlib-mode", "source"]), 0)
        calls = [json.loads(line) for line in self.trace.read_text().splitlines()]
        self.assertEqual(sum("--stdlib-only" in call for call in calls), 0)
        self.assertEqual(sum("--stdlib-from-source" in call for call in calls), 4)

    def test_source_mode_does_not_claim_shared_library_verification(self):
        self.assertEqual(self.run_gate(lane="all", extra=["--stdlib-mode", "source"]), 0)
        self.assertFalse(self.report()["complete_verification"])
        self.assertTrue(self.report()["full_corpus"])
        self.assertEqual(len(self.report()["results"]), 6)


if __name__ == "__main__":
    unittest.main()
