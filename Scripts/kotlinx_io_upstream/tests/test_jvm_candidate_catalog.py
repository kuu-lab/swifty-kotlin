#!/usr/bin/env python3
"""Check the explicit macOS candidate mapping for JVM-only Sink tests."""

import hashlib
import importlib.util
from pathlib import Path
import sys
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "prepare_jvm_candidate_catalog.py"
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("kio_jvm_candidate_catalog", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(MODULE)


class JvmCandidateCatalogTests(unittest.TestCase):
    def test_each_jvm_function_keeps_both_factory_invocations(self):
        rows = []
        for source_id in MODULE.SOURCE_IDS:
            method = source_id.rsplit("#", 1)[1]
            for concrete_class in ("kotlinx.io.BufferSinkTestJVM", "kotlinx.io.RealSinkTestJVM"):
                rows.append({
                    "execution_id": f"[engine:junit-jupiter]/[class:{concrete_class}]/[method:{method}()]",
                    "upstream_id": source_id,
                    "upstream_path": "core/jvm/test/AbstractSinkTestJVM.kt",
                    "source_set": "jvm",
                    "concrete_class": concrete_class,
                    "declaring_class": "kotlinx.io.AbstractSinkTestJVM",
                    "method_name": method,
                    "parameter_types": "",
                    "git_blob_sha": "locked-blob",
                })
        reference_bytes = b"locked-jvm-catalog"
        lock = {
            "commit": "362bdc35e159bad6da1e08101c8321792d762281",
            "jvm_execution_catalog_sha256": hashlib.sha256(reference_bytes).hexdigest(),
        }
        catalog = MODULE.build_catalog(lock, rows, reference_bytes)
        self.assertEqual(catalog["execution_count"], 20)
        self.assertEqual(len({row["upstream_id"] for row in catalog["executions"]}), 10)
        self.assertTrue(all("[engine:kswiftk-macos-native]" in row["execution_id"]
                            for row in catalog["executions"]))
        self.assertEqual({row["reference_execution_id"] for row in catalog["executions"]},
                         {row["execution_id"] for row in rows})

    def test_missing_target_function_is_rejected(self):
        lock = {
            "commit": "362bdc35e159bad6da1e08101c8321792d762281",
            "jvm_execution_catalog_sha256": hashlib.sha256(b"catalog").hexdigest(),
        }
        with self.assertRaisesRegex(ValueError, "missing"):
            MODULE.build_catalog(lock, [], b"catalog")


if __name__ == "__main__":
    unittest.main()
