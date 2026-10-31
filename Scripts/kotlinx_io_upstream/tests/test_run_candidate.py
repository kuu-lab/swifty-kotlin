import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apple"))
from run_candidate import testing_counts


EXPECTED_METHODS = {"sixAppleExtensionsHaveRealTypedPublicSourceAndImportedShapes": 2}


def pass_log(icon):
    """A Swift Testing pass log where every status line uses the given icon."""
    return (
        f"{icon}Test run started.\n"
        f"{icon}Suite IOAppleAPIContractTests started.\n"
        f"{icon}Test sixAppleExtensionsHaveRealTypedPublicSourceAndImportedShapes(library:)"
        " with 2 test cases passed after 570.063 seconds.\n"
        f"{icon}Suite IOAppleAPIContractTests passed after 570.063 seconds.\n"
        f"{icon}Test run with 1 test in 1 suite passed after 570.063 seconds.\n"
    )


# Classic output (Swift <= 6.3 and default streams): BMP check mark + one space.
CLASSIC_ICON = "✔ "
# SF Symbols output (SWT_SF_SYMBOLS_ENABLED on newer toolchains): private-use
# glyphs in supplementary plane 16 followed by two spaces; observed pass glyph
# U+10105B (bytes f4 81 81 9b) and failure glyph U+102884 (bytes f4 80 a2 84).
SF_PASS_ICON = "\U0010105B  "
SF_FAIL_ICON = "\U00102884  "


class TestingCountsTests(unittest.TestCase):
    def assert_counts(self, counts):
        self.assertEqual(counts["methods"], 1)
        self.assertEqual(counts["cases"], 2)
        self.assertEqual(counts["suites"], 1)
        self.assertEqual(counts["successful_methods_and_cases"], EXPECTED_METHODS)
        self.assertEqual(counts["Swift_Testing_final_summary"], ("1", "1", "570.063"))

    def test_classic_checkmark_log_is_accepted(self):
        self.assert_counts(testing_counts(pass_log(CLASSIC_ICON), EXPECTED_METHODS))

    def test_sf_symbols_private_use_log_is_accepted(self):
        # The receipt metadata.stdout on Swift 6.4 CLT carries U+10105B icons.
        self.assert_counts(testing_counts(pass_log(SF_PASS_ICON), EXPECTED_METHODS))

    def test_log_surrounded_by_other_output_is_accepted(self):
        log = "Build complete! (3.96s)\n" + pass_log(CLASSIC_ICON) + "some stderr line\n"
        self.assert_counts(testing_counts(log, EXPECTED_METHODS))

    def test_missing_pass_summary_is_rejected(self):
        log = f"{CLASSIC_ICON}Test run started.\n"
        with self.assertRaisesRegex(RuntimeError, "PASS summary"):
            testing_counts(log, EXPECTED_METHODS)

    def test_multiple_pass_summaries_are_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "PASS summary"):
            testing_counts(pass_log(CLASSIC_ICON) + pass_log(CLASSIC_ICON), EXPECTED_METHODS)

    def test_classic_failure_log_is_rejected(self):
        log = (
            f"{CLASSIC_ICON}Test run started.\n"
            f"✘ Test sixAppleExtensionsHaveRealTypedPublicSourceAndImportedShapes(library:)"
            " failed after 570.063 seconds with 1 issue.\n"
            f"✘ Test run with 1 test in 1 suite failed after 570.063 seconds with 1 issue.\n"
        )
        with self.assertRaisesRegex(RuntimeError, "PASS summary"):
            testing_counts(log, EXPECTED_METHODS)

    def test_sf_symbols_failure_log_is_rejected(self):
        # Failed status lines read "failed after ... with N issue." under a
        # different PUA glyph; they must never satisfy the pass patterns.
        log = (
            f"{SF_FAIL_ICON}Test sixAppleExtensionsHaveRealTypedPublicSourceAndImportedShapes(library:)"
            " failed after 570.063 seconds with 1 issue.\n"
            f"{SF_FAIL_ICON}Suite IOAppleAPIContractTests failed after 570.063 seconds with 1 issue.\n"
            f"{SF_FAIL_ICON}Test run with 1 test in 1 suite failed after 570.063 seconds with 1 issue.\n"
        )
        with self.assertRaisesRegex(RuntimeError, "PASS summary"):
            testing_counts(log, EXPECTED_METHODS)

    def test_zero_test_summary_is_rejected(self):
        log = (
            f"{CLASSIC_ICON}Test run with 0 tests in 1 suite passed after 0.001 seconds.\n"
        )
        with self.assertRaisesRegex(RuntimeError, "scope"):
            testing_counts(log, EXPECTED_METHODS)

    def test_missing_method_line_is_rejected(self):
        log = (
            f"{CLASSIC_ICON}Suite IOAppleAPIContractTests passed after 570.063 seconds.\n"
            f"{CLASSIC_ICON}Test run with 1 test in 1 suite passed after 570.063 seconds.\n"
        )
        with self.assertRaisesRegex(RuntimeError, "scope"):
            testing_counts(log, EXPECTED_METHODS)

    def test_extra_successful_method_is_rejected(self):
        log = pass_log(CLASSIC_ICON) + (
            f"{CLASSIC_ICON}Test unrelatedMethod() passed after 0.001 seconds.\n"
        )
        with self.assertRaisesRegex(RuntimeError, "scope"):
            testing_counts(log, EXPECTED_METHODS)

    def test_duplicate_successful_method_is_rejected(self):
        line = (f"{CLASSIC_ICON}Test sixAppleExtensionsHaveRealTypedPublicSourceAndImportedShapes(library:)"
                " with 2 test cases passed after 1.000 seconds.\n")
        log = (
            line + line +
            f"{CLASSIC_ICON}Test run with 1 test in 1 suite passed after 1.000 seconds.\n"
        )
        with self.assertRaisesRegex(RuntimeError, "Duplicate"):
            testing_counts(log, EXPECTED_METHODS)

    def test_wrong_case_count_is_rejected(self):
        log = (
            f"{CLASSIC_ICON}Test sixAppleExtensionsHaveRealTypedPublicSourceAndImportedShapes(library:)"
            " with 3 test cases passed after 570.063 seconds.\n"
            f"{CLASSIC_ICON}Test run with 1 test in 1 suite passed after 570.063 seconds.\n"
        )
        with self.assertRaisesRegex(RuntimeError, "scope"):
            testing_counts(log, EXPECTED_METHODS)


if __name__ == "__main__":
    unittest.main()
