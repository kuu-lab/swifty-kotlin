#!/usr/bin/env python3
"""Regression tests for importing the pinned upstream case catalog."""

from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import import_inventory  # noqa: E402


class ImportInventoryTests(unittest.TestCase):
    def test_expands_catalog_ids_and_preserves_unverified_or_unsupported_status(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kio-inventory-test-") as tmp:
            temp = Path(tmp)
            index_path = temp / "test-index.json"
            index = {
                "repository": "https://github.com/Kotlin/kotlinx-io",
                "tag": "0.9.1",
                "commit": import_inventory.EXPECTED_COMMIT,
                "files": [
                    {"path": "core/common/test/BufferTest.kt", "gitBlobSha": "a" * 40, "size": 100, "testNames": ["readByte", "readAtMostTo"], "classNames": ["BufferTest"]},
                    {"path": "core/common/test/samples/Samples.kt", "gitBlobSha": "b" * 40, "size": 50, "testNames": ["readSample"], "classNames": ["Samples"]},
                    {"path": "core/apple/test/AppleTest.kt", "gitBlobSha": "c" * 40, "size": 70, "testNames": ["streamSource"], "classNames": ["AppleTest"]},
                    {"path": "core/jvm/test/files/SmokeFileTestWindowsJVM.kt", "gitBlobSha": "d" * 40, "size": 30, "testNames": ["parentPath"], "classNames": ["SmokeFileTestWindowsJVM"]},
                    {"path": "core/native/test/util.kt", "gitBlobSha": "e" * 40, "size": 20, "testNames": [], "classNames": []},
                    {"path": "core/js/test/JsBufferTest.kt", "gitBlobSha": "f" * 40, "size": 40, "testNames": ["readByte"], "classNames": ["JsBufferTest"]},
                    {"path": "core/nativeNonApple/test/NonAppleBufferTest.kt", "gitBlobSha": "1" * 40, "size": 45, "testNames": ["readByte"], "classNames": ["NonAppleBufferTest"]},
                ],
            }
            index_bytes = (json.dumps(index, separators=(",", ":")) + "\n").encode("utf-8")
            index_path.write_bytes(index_bytes)
            lock_path = temp / "lock.json"
            lock_path.write_text(
                json.dumps(
                    {
                        "tag": "0.9.1",
                        "commit": import_inventory.EXPECTED_COMMIT,
                        "upstreamTestsIndexSha256": hashlib.sha256(index_bytes).hexdigest(),
                        "mavenArtifacts": [
                            {"coordinate": "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1", "url": "https://example.invalid/core.jar", "sha256": "f" * 64}
                        ],
                    }
                ),
                encoding="utf-8",
            )
            crosswalk_path = temp / "api.tsv"
            crosswalk_path.write_text(
                "upstream_test_refs\tlocal_test_refs\tlocal_candidate_refs\n"
                "core/common/test/BufferTest.kt#readByte\tTests/CompilerBackendTests/Integration/Buffer.swift\tScripts/diff_cases/kotlinx_io_buffer_basic.kt\n",
                encoding="utf-8",
            )

            matrix = import_inventory.build_map(index_path, crosswalk_path, lock_path)
            cases = {case["upstream_id"]: case for case in matrix["cases"]}
            self.assertEqual(len(cases), 7)
            self.assertEqual(matrix["catalog"]["source_file_count"], 7)
            self.assertEqual(matrix["catalog"]["inventory_only_source_count"], 1)
            self.assertEqual(matrix["catalog"]["parameterized_factory_case_count"], None)
            self.assertEqual(
                matrix["catalog"]["local_crosswalk_sha256"],
                hashlib.sha256(crosswalk_path.read_bytes()).hexdigest(),
            )
            self.assertEqual(len(matrix["reference_artifacts"]), 1)
            mapped_candidate = cases["core/common/test/BufferTest.kt#readByte"]
            self.assertEqual(mapped_candidate["disposition"], "unmapped")
            self.assertEqual(mapped_candidate["mapping"]["status"], "candidate-unverified")
            self.assertFalse(mapped_candidate["mapping"]["verified_assertion_mapping"])
            self.assertEqual(
                cases["core/common/test/samples/Samples.kt#readSample"]["test_kind"],
                "sample",
            )
            self.assertEqual(cases["core/apple/test/AppleTest.kt#streamSource"]["disposition"], "unsupported")
            self.assertEqual(cases["core/js/test/JsBufferTest.kt#readByte"]["platform"], "js")
            self.assertEqual(cases["core/js/test/JsBufferTest.kt#readByte"]["disposition"], "unsupported")
            self.assertEqual(
                cases["core/nativeNonApple/test/NonAppleBufferTest.kt#readByte"]["platform"],
                "native-nonapple",
            )
            self.assertEqual(
                cases["core/nativeNonApple/test/NonAppleBufferTest.kt#readByte"]["disposition"],
                "unsupported",
            )
            self.assertEqual(import_inventory.platform_for("core/native/test/util.kt"), "native")
            self.assertEqual(
                import_inventory.platform_for("core/iosSimulatorArm64/test/PlatformTest.kt"),
                "ios-simulator-arm64",
            )
            self.assertEqual(
                cases["core/jvm/test/files/SmokeFileTestWindowsJVM.kt#parentPath"]["disposition"],
                "unsupported",
            )

    def test_rejects_a_mismatched_upstream_ref(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kio-inventory-test-") as tmp:
            index_path = Path(tmp) / "test-index.json"
            index_path.write_text(json.dumps({"tag": "0.9.1", "commit": "wrong", "files": []}), encoding="utf-8")
            with self.assertRaises(import_inventory.CatalogImportError):
                import_inventory.build_map(index_path, None)


if __name__ == "__main__":
    unittest.main(verbosity=2)
