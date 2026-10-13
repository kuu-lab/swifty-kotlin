#!/usr/bin/env python3
"""Do not turn missing, skipped, failed, or unfinished Native tests into PASS."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_native_reference as runner


class NativeReferenceTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
