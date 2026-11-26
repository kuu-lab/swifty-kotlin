#!/usr/bin/env python3
"""Focused regression tests for the Apple candidate log parser."""
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import unittest


SCRIPT = Path(__file__).with_name("run_candidate.py")
SPEC = spec_from_file_location("apple_run_candidate", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
RUN_CANDIDATE = module_from_spec(SPEC)
SPEC.loader.exec_module(RUN_CANDIDATE)


class TestingCountsTests(unittest.TestCase):
    def test_ignores_empty_summaries_from_other_test_products(self):
        log = "\n".join([
            "✔ Test focusedMethod() passed after 0.1 seconds.",
            "✔ Suite IOAppleAPIContractTests passed after 0.1 seconds.",
            "✔ Test run with 1 test in 1 suite passed after 0.1 seconds.",
            "✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.",
            "✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.",
        ])

        counts = RUN_CANDIDATE.testing_counts(log, {"focusedMethod": 1})

        self.assertEqual(counts["successful_methods_and_cases"], {"focusedMethod": 1})
        self.assertEqual(counts["duration_seconds"], 0.1)

    def test_rejects_multiple_nonempty_summaries(self):
        log = "\n".join([
            "✔ Test run with 1 test in 1 suite passed after 0.1 seconds.",
            "✔ Test run with 2 tests in 1 suite passed after 0.2 seconds.",
        ])

        with self.assertRaisesRegex(RuntimeError, "exactly one non-empty"):
            RUN_CANDIDATE.testing_counts(log, {"focusedMethod": 1})


class StageCommandTests(unittest.TestCase):
    def test_names_the_stage_test_product_and_matches_only_expected_methods(self):
        argv = RUN_CANDIDATE.stage_command(
            "CompilerBackendTests", "IOAppleInteropExecutionTests", {"lane": 4, "other": 2})

        self.assertEqual(argv[argv.index("--test-product") + 1], "CompilerBackendTests")
        pattern = argv[argv.index("--filter") + 1]
        self.assertRegex("CompilerBackendTests.IOAppleInteropExecutionTests/lane(mode:)", pattern)
        self.assertRegex("CompilerBackendTests.IOAppleInteropExecutionTests/other", pattern)
        self.assertNotRegex("CompilerBackendTests.IOAppleInteropExecutionTests/laneTwo(mode:)", pattern)
        self.assertNotRegex("RuntimeTests.IOAppleInteropExecutionTests/lane(mode:)", pattern)


if __name__ == "__main__":
    unittest.main()
