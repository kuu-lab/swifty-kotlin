#!/usr/bin/env python3
"""Verify that generated F01 consumers cover the pinned ledger deterministically."""

import importlib.util
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent


def load_generator():
    spec = importlib.util.spec_from_file_location("io_f01_consumers", HERE / "generate_f01_consumers.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class F01ConsumerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generator = load_generator()
        cls.outputs, cls.counts = cls.generator.generate()

    def test_all_public_source_signatures_have_scope_tagged_consumers(self):
        self.assertEqual(
            self.counts,
            {
                "positive_common": 250,
                "positive_jvm": 235,
                "positive_apple": 6,
                "positive_platform": 2,
                "negative_deprecated": 2,
                "negative_opt_in": 12,
                "negative_opt_in_warning": 6,
                "negative_opt_in_error": 6,
                "negative_internal": 19,
                "negative_invalid": 5,
            },
        )
        manifest = self.outputs["consumer-manifest.json"]
        for row_id in (
            "klib-00fa8d5d9f11e43f",  # Sink.write with upstream default parameters.
            "klib-a6ee175ecb9390e8",  # Source.readByteString.
            "klib-d0fcd12bd08dd253",  # ByteStringBuilder.append defaults.
        ):
            self.assertIn(row_id, manifest)

    def test_negative_corpus_covers_deprecation_opt_in_internal_and_invalid_apis(self):
        self.assertIn("Path.source", self.outputs["negative-deprecated.kt"])
        self.assertIn("Path.sink", self.outputs["negative-deprecated.kt"])
        opt_in = self.outputs["negative-opt-in.kt"]
        for marker in self.generator.API_OPT_IN_MARKERS:
            self.assertIn(marker, opt_in)
        warning_opt_in = self.outputs["negative-opt-in-warning.kt"]
        self.assertIn("DelicateIoApi", warning_opt_in)
        self.assertIn("UnsafeIoApi", warning_opt_in)
        self.assertNotIn("InternalIoApi", warning_opt_in)
        error_opt_in = self.outputs["negative-opt-in-error.kt"]
        self.assertIn("InternalIoApi", error_opt_in)
        self.assertIn("UnsafeByteStringApi", error_opt_in)
        self.assertNotIn("DelicateIoApi", error_opt_in)
        internal = self.outputs["negative-internal.kt"]
        self.assertEqual(internal.count("// Ledger internal-"), 19)
        invalid = self.outputs["negative-invalid.kt"]
        guards = self.generator.read_invalid_guards()
        self.assertEqual(len(guards), 5)
        for guard in guards:
            self.assertIn(f"// Guard {guard['guard_id']}:", invalid)
            self.assertIn(guard["call"], invalid)
            self.assertIn(guard["guard_id"], self.outputs["consumer-manifest.json"])

    def test_checked_in_consumers_match_the_ledger(self):
        self.assertFalse(list((HERE / "f01_consumers").glob("*.tmp")))
        for name, expected in self.outputs.items():
            self.assertEqual((HERE / "f01_consumers" / name).read_text(), expected, name)


if __name__ == "__main__":
    unittest.main()
