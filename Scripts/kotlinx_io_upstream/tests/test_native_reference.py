#!/usr/bin/env python3
"""Do not turn missing, skipped, failed, or unfinished Native tests into PASS."""
from pathlib import Path
import json
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_native_reference as runner


class NativeReferenceTests(unittest.TestCase):
    def test_exact_execution_selection_is_catalog_bound(self):
        catalog = [{"execution_id": "one"}, {"execution_id": "two"}]
        self.assertEqual(runner.select_execution_rows(catalog, ["two"]), [catalog[1]])
        with self.assertRaisesRegex(ValueError, "unique"):
            runner.select_execution_rows(catalog, ["one", "one"])
        with self.assertRaisesRegex(ValueError, "unknown locked execution ID"):
            runner.select_execution_rows(catalog, ["missing"])

    def event(self, event, attributes):
        return f"##teamcity[{event} {attributes}]\n"

    def test_factory_identity_list_dump_and_missing_discovery(self):
        listed = runner.parse_list("io.Buffer.\n  read\nio.Peek.\n  read\n")
        self.assertEqual(listed, ["io.Buffer.read", "io.Peek.read"])
        runner.check_ids(listed, set(listed), "test")
        with self.assertRaisesRegex(ValueError, "missing"):
            runner.check_ids(listed[:1], set(listed), "test")
        with self.assertRaisesRegex(ValueError, "duplicate"):
            runner.check_ids(listed + listed, set(listed), "test")

    def test_pass_fail_skip_and_escaped_failure_are_preserved(self):
        text = self.event("testSuiteStarted", "name='io.Suite'")
        for name, failure in (("pass", False), ("fail", True)):
            text += self.event("testStarted", f"name='{name}' locationHint='ktest:test://io.Suite.{name}'")
            if failure:
                text += self.event("testFailed", "name='fail' message='can|'t || |[x|]' details='line1|nline2|r'")
            text += self.event("testFinished", f"name='{name}' duration='3'")
        text += self.event("testIgnored", "name='skip' message='platform'")
        text += self.event("testSuiteFinished", "name='io.Suite'")
        rows = runner.parse_teamcity(text)
        self.assertEqual([row["status"] for row in rows], ["PASS", "FAIL", "SKIP"])
        self.assertEqual(rows[1]["message"], "can't | [x]")
        self.assertEqual(rows[1]["details"], "line1\nline2\r")

    def test_unfinished_missing_start_duplicate_and_bad_identity_are_rejected(self):
        begin = self.event("testSuiteStarted", "name='io.Suite'")
        start = self.event("testStarted", "name='read'")
        end = self.event("testSuiteFinished", "name='io.Suite'")
        self.assertEqual(runner.parse_teamcity(begin + start + end)[0]["status"], "NOT_FINISHED")
        for text in (begin + start, begin + start + start + end,
            begin + self.event("testFinished", "name='read'") + end,
            begin + self.event("testStarted", "name='read' locationHint='ktest:test://wrong'") + end):
            with self.assertRaises(ValueError):
                runner.parse_teamcity(text)

    def test_exact_native_selection_runs_each_locked_id_separately(self):
        expected = [{"execution_id": "io.Suite.first"}, {"execution_id": "io.Suite.second"}]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            output.mkdir(exist_ok=True)
            commands = []

            def fake_execute(command, target, stage, timeout, overrides):
                commands.append(command)
                identifier = command[-1].removeprefix("--ktest_filter=")
                self.assertIn(identifier, {row["execution_id"] for row in expected})
                target.joinpath(f"{stage}.stdout").write_text(
                    "##teamcity[testSuiteStarted name='io.Suite']\n"
                    f"##teamcity[testStarted name='{identifier.rsplit('.', 1)[1]}']\n"
                    f"##teamcity[testFinished name='{identifier.rsplit('.', 1)[1]}' duration='1']\n"
                    "##teamcity[testSuiteFinished name='io.Suite']\n"
                )
                target.joinpath(f"{stage}.stderr").write_text("")
                target.joinpath(f"{stage}.result.json").write_text(json.dumps(
                    {"exitcode": 0, "timeout": False, "seconds": 0.01}
                ))
                return 0

            with patch.object(runner, "execute", side_effect=fake_execute):
                code, results = runner.run_native_tests(
                    Path("tests.kexe"), expected, output, 10, {}, exact_selection=True
                )

            self.assertEqual(code, 0)
            self.assertEqual([row["status"] for row in results], ["PASS", "PASS"])
            self.assertEqual(len(commands), 2)
            self.assertEqual([command[-1] for command in commands], [
                "--ktest_filter=io.Suite.first", "--ktest_filter=io.Suite.second",
            ])
            self.assertEqual(json.loads((output / "run.commands.json").read_text()), commands)
            self.assertEqual(json.loads((output / "run.result.json").read_text())["exitcode"], 0)


if __name__ == "__main__":
    unittest.main()
