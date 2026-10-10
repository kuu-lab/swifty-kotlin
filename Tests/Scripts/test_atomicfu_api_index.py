#!/usr/bin/env python3
"""Focused tests for the pinned atomicfu declaration-index generator."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts"))

import generate_atomicfu_api_index as api_index  # noqa: E402


class AtomicfuAPIIndexTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.klib = (api_index.REFERENCE / "atomicfu.klib.api").read_bytes()
        cls.document = api_index.build_declaration_index(cls.klib)
        cls.rows = cls.document["declarations"]
        cls.by_symbol = {}
        for row in cls.rows:
            cls.by_symbol.setdefault(row["api_symbol"], []).append(row)

    def test_generated_index_is_deterministic_and_preserves_declaration_identities(self) -> None:
        self.assertEqual(
            self.document["summary"],
            {
                "common_native_declarations": 150,
                "common_native_unique_signatures": 126,
                "inherited_js_wasm_exclusions": 5,
                "total_api_identity_rows": 155,
                "legacy_flat_unique_signatures": 130,
            },
        )
        self.assertEqual(api_index.render_index(self.klib), api_index.render_index(self.klib))
        self.assertEqual(len(self.rows), 155)
        self.assertEqual(len({row["signature"] for row in self.rows}), 130)
        value_rows = [row for row in self.rows if row["signature"] == "final var value"]
        self.assertEqual(len(value_rows), 4)
        self.assertEqual(len({row["api_identity"] for row in value_rows}), 4)

    def test_nested_js_wasm_targets_do_not_leak_into_common_native_scope(self) -> None:
        excluded = [row for row in self.rows if row["scope"] != "common-native"]
        self.assertEqual(
            {row["api_symbol"] for row in excluded},
            {
                "kotlinx.atomicfu.locks/Lock.<get-Lock>",
                "kotlinx.atomicfu.locks/ReentrantLock.<init>",
                "kotlinx.atomicfu.locks/ReentrantLock.lock",
                "kotlinx.atomicfu.locks/ReentrantLock.tryLock",
                "kotlinx.atomicfu.locks/ReentrantLock.unlock",
            },
        )
        for row in excluded:
            self.assertEqual(row["klib_target_expressions"], ["[js, wasmJs, wasmWasi]"])

    def test_every_row_has_signature_kind_overload_visibility_and_pinned_source(self) -> None:
        valid_kinds = {"annotation_class", "class", "constructor", "function", "object", "property"}
        for row in self.rows:
            self.assertTrue(row["signature"])
            self.assertTrue(row["api_identity"])
            self.assertIn(row["kind"], valid_kinds)
            self.assertTrue(row["overload_group"])
            self.assertGreaterEqual(row["overload_index"], 1)
            self.assertGreaterEqual(row["overload_count"], row["overload_index"])
            self.assertIn(row["kotlin_visibility"], {"public", "internal", "mixed"})
            self.assertTrue(row["source_provenance"])
            for source in row["source_provenance"]:
                self.assertEqual(source["git_blob_sha1"], api_index.SOURCE_BLOBS[source["path"]])
                self.assertIn(source["visibility"], {"public", "internal", "protected", "private"})
                self.assertIn("annotation_evidence", source)
                self.assertIsInstance(source["annotations"], list)
                self.assertIsInstance(source["inherited_annotations"], list)

    def test_visibility_annotations_and_overloads_are_tracked_per_declaration(self) -> None:
        atomic_a = self.by_symbol["kotlinx.atomicfu/AtomicInt.a"][0]
        native_a = next(
            source for source in atomic_a["source_provenance"] if source["path"].endswith("AtomicFU.kt")
        )
        self.assertEqual(atomic_a["kotlin_visibility"], "internal")
        self.assertEqual(native_a["annotations"], ["PublishedApi"])

        append_rows = self.by_symbol["kotlinx.atomicfu/TraceBase.append"]
        self.assertEqual(len(append_rows), 4)
        self.assertTrue(
            all(
                row["source_provenance"][0]["annotations"] == ["OptionalJsName"]
                for row in append_rows
            )
        )

        parking = self.by_symbol["kotlinx.atomicfu.locks/ParkingSupport.park"][0]
        self.assertTrue(
            all(
                "ExperimentalThreadBlockingApi" in source["inherited_annotations"]
                for source in parking["source_provenance"]
            )
        )

        array_getter = self.by_symbol["kotlinx.atomicfu/AtomicArray.size.<get-size>"][0]
        self.assertEqual(
            array_getter["source_provenance"][0]["inherited_annotations"], ["OptionalJsName"]
        )

        atomic_overloads = self.by_symbol["kotlinx.atomicfu/atomic"]
        self.assertEqual({row["overload_count"] for row in atomic_overloads}, {8})
        get_and_update = self.by_symbol["kotlinx.atomicfu/getAndUpdate"]
        self.assertEqual({row["overload_count"] for row in get_and_update}, {4})

    def test_empty_annotation_lists_explicitly_record_source_evidence(self) -> None:
        unannotated = next(
            source
            for row in self.rows
            for source in row["source_provenance"]
            if not source["annotations"]
        )
        self.assertIn("no direct annotation", unannotated["annotation_evidence"])
        self.assertIn(unannotated["path"], api_index.SOURCE_BLOBS)


if __name__ == "__main__":
    unittest.main()
