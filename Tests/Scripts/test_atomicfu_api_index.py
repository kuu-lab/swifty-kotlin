#!/usr/bin/env python3
"""Focused tests for the pinned atomicfu declaration-index generator."""

from __future__ import annotations

import sys
import copy
import json
import tempfile
from unittest.mock import patch
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Scripts"))

import generate_atomicfu_api_index as api_index  # noqa: E402
import atomicfu_source_evidence as source_evidence  # noqa: E402


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
            self.assertIn(row["kotlin_visibility"], {"public", "internal", "mixed", None})
            self.assertTrue(row["source_provenance"])
            for source in row["source_provenance"]:
                self.assertEqual(source["git_blob_sha1"], api_index.SOURCE_BLOBS[source["path"]])
                if source["evidence_status"] == "unavailable-js-wasm-exclusion":
                    self.assertNotEqual(row["scope"], "common-native")
                    self.assertIsNone(source["annotations"])
                    self.assertIsNone(source["annotation_records"])
                    self.assertIsNone(source["visibility"])
                    continue
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
                "ExperimentalThreadBlockingApi" in [a["name"] for a in source["enclosing_annotation_records"]]
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
            if source["evidence_status"] == "verified-pinned-source" and not source["annotations"]
        )
        self.assertIn("exact pinned declaration span", unannotated["annotation_evidence"])
        self.assertIn(unannotated["path"], api_index.SOURCE_BLOBS)

    def test_object_and_exact_trace_source_declarations(self) -> None:
        for symbol in ("kotlinx.atomicfu.locks/ParkingSupport", "kotlinx.atomicfu/TraceBase.None"):
            self.assertEqual(self.by_symbol[symbol][0]["kind"], "object")
        for row in self.rows:
            if row["api_symbol"].startswith("kotlinx.atomicfu/TraceBase"):
                self.assertEqual([s["path"] for s in row["source_provenance"]], [
                    "atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/Trace.common.kt",
                ])
        for symbol in ("kotlinx.atomicfu/Trace", "kotlinx.atomicfu/traceFormatDefault.<get-traceFormatDefault>"):
            self.assertEqual({s["path"] for s in self.by_symbol[symbol][0]["source_provenance"]}, {
                "atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/Trace.common.kt",
                "atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/Trace.kt",
            })
        for family in ("AtomicRef", "AtomicBoolean", "AtomicInt", "AtomicLong"):
            refs = self.by_symbol[f"kotlinx.atomicfu/{family}.toString"][0]["source_provenance"]
            self.assertEqual([s["path"] for s in refs], [
                "atomicfu/src/nativeMain/kotlin/kotlinx/atomicfu/AtomicFU.kt",
            ])

    def test_constructor_annotations_use_the_constructor_span(self) -> None:
        for name, line in (("AtomicIntArray", 532), ("AtomicLongArray", 563)):
            ref = self.by_symbol[f"kotlinx.atomicfu/{name}.<init>"][0]["source_provenance"][0]
            self.assertEqual(ref["annotations"], ["Deprecated"])
            self.assertEqual(ref["declaration"]["line"], line)
            arguments = ref["annotation_records"][0]["arguments"]
            self.assertEqual(next(a["expression"] for a in arguments if a["name"] == "level"), "DeprecationLevel.WARNING")
            self.assertEqual(next(a["expression"] for a in arguments if a["name"] == "replaceWith"),
                             f'ReplaceWith("kotlin.concurrent.atomics.{name}(size)")')
        boolean = self.by_symbol["kotlinx.atomicfu/AtomicBooleanArray.<init>"][0]["source_provenance"][0]
        self.assertEqual(boolean["annotations"], [])
        self.assertEqual(boolean["declaration"]["mode"], "implicit_constructor")
        self.assertEqual({a["name"] for a in boolean["enclosing_annotation_records"]}, {"Suppress", "OptionalJsName", "Deprecated"})

    def test_binary_retention_error_opt_in_and_symbolic_arguments_are_preserved(self) -> None:
        optional = self.by_symbol["kotlinx.atomicfu/OptionalJsName"][0]["source_provenance"][0]
        annotations = {a["name"]: a for a in optional["annotation_records"]}
        self.assertEqual(annotations["Retention"]["arguments"], [{"name": None, "expression": "AnnotationRetention.BINARY"}])
        self.assertEqual([a["expression"] for a in annotations["Target"]["arguments"]], [
            "AnnotationTarget.CLASS", "AnnotationTarget.FUNCTION", "AnnotationTarget.PROPERTY",
            "AnnotationTarget.CONSTRUCTOR", "AnnotationTarget.PROPERTY_GETTER", "AnnotationTarget.PROPERTY_SETTER",
        ])
        marker = self.by_symbol["kotlinx.atomicfu.locks/ExperimentalThreadBlockingApi"][0]["source_provenance"][0]
        annotations = {a["name"]: a for a in marker["annotation_records"]}
        self.assertEqual(annotations["Retention"]["arguments"][0]["expression"], "AnnotationRetention.BINARY")
        opt_in = {a["name"]: a["expression"] for a in annotations["RequiresOptIn"]["arguments"]}
        self.assertEqual(opt_in["level"], "RequiresOptIn.Level.ERROR")
        self.assertEqual(opt_in["message"], '"This API is experimental. It is low-level and might change in the future."')
        self.assertIn("AnnotationTarget.TYPEALIAS", [a["expression"] for a in annotations["Target"]["arguments"]])
        append = sorted(self.by_symbol["kotlinx.atomicfu/TraceBase.append"], key=lambda r: r["overload_index"])
        for i, row in enumerate(append, 1):
            argument = row["source_provenance"][0]["annotation_records"][0]["arguments"][0]
            self.assertEqual(argument["expression"], f"TRACE_APPEND_{i}")
            self.assertEqual(argument["constant_reference"]["expression"], '"atomicfu\\$Trace\\$append\\$' + str(i) + '"')

    def test_semantic_checker_rejects_mutually_consistent_wrong_facts(self) -> None:
        source_evidence.validate_source_semantics(self.document)
        mutations = []
        wrong = copy.deepcopy(self.document)
        next(r for r in wrong["declarations"] if r["api_symbol"] == "kotlinx.atomicfu.locks/ParkingSupport")["kind"] = "class"
        mutations.append(wrong)
        wrong = copy.deepcopy(self.document)
        row = next(r for r in wrong["declarations"] if r["api_symbol"] == "kotlinx.atomicfu/AtomicIntArray.<init>")
        row["source_provenance"][0]["annotations"].append("OptionalJsName")
        mutations.append(wrong)
        wrong = copy.deepcopy(self.document)
        ref = next(r for r in wrong["declarations"] if r["api_symbol"] == "kotlinx.atomicfu.locks/ExperimentalThreadBlockingApi")["source_provenance"][0]
        next(a for a in ref["annotation_records"] if a["name"] == "Retention")["arguments"][0]["expression"] = "AnnotationRetention.RUNTIME"
        mutations.append(wrong)
        wrong = copy.deepcopy(self.document)
        next(r for r in wrong["declarations"] if r["api_symbol"] == "kotlinx.atomicfu/TraceBase")["source_provenance"] = []
        mutations.append(wrong)
        for wrong in mutations:
            # This predicate is independent of render_index, so regenerating a
            # JSON from the same wrong rule cannot make source semantics green.
            with self.assertRaises(ValueError):
                source_evidence.validate_source_semantics(wrong)

    def test_actual_source_overload_and_receiver_substitution_are_rejected(self) -> None:
        _, sources = source_evidence.load_sources()
        anchors = json.loads((api_index.REFERENCE / "atomicfu.source-anchors.json").read_text())
        path = "atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/AtomicFU.common.kt"
        identity = "kotlinx.atomicfu/atomic|atomic(kotlin.Int){}[0]"
        wrong = copy.deepcopy(anchors)
        wrong[identity][path] = anchors["kotlinx.atomicfu/atomic|atomic(kotlin.Boolean){}[0]"][path]
        with self.assertRaisesRegex(ValueError, "overload type"):
            source_evidence.source_fact(identity, path, "common", sources, wrong)
        identity = next(k for k in anchors if k.startswith("kotlinx.atomicfu/update|update@kotlinx.atomicfu.AtomicInt("))
        other = next(k for k in anchors if k.startswith("kotlinx.atomicfu/update|update@kotlinx.atomicfu.AtomicBoolean("))
        wrong = copy.deepcopy(anchors)
        wrong[identity][path] = anchors[other][path]
        with self.assertRaisesRegex(ValueError, "extension receiver"):
            source_evidence.source_fact(identity, path, "common", sources, wrong)
        identity = "kotlinx.atomicfu/TraceBase.append|append(kotlin.Any){}[0]"
        other = "kotlinx.atomicfu/TraceBase.append|append(kotlin.Any;kotlin.Any){}[0]"
        path = "atomicfu/src/commonMain/kotlin/kotlinx/atomicfu/Trace.common.kt"
        wrong = copy.deepcopy(anchors)
        wrong[identity][path] = anchors[other][path]
        with self.assertRaisesRegex(ValueError, "arity"):
            source_evidence.source_fact(identity, path, "common", sources, wrong)

    def test_pinned_source_bytes_and_missing_js_source_are_enforced(self) -> None:
        manifest, sources = source_evidence.load_sources()
        self.assertEqual(len(sources), 13)
        missing = [s for s in manifest["sources"] if s["local_path"] is None]
        self.assertEqual(len(missing), 1)
        self.assertIn("jsAndWasmSharedMain", missing[0]["path"])
        refs = [s for row in self.rows for s in row["source_provenance"] if s["evidence_status"] == "unavailable-js-wasm-exclusion"]
        self.assertEqual(len(refs), 5)
        self.assertTrue(all(s["annotation_records"] is None for s in refs))
        with tempfile.TemporaryDirectory() as folder:
            source = next(iter(sources.values()))
            record = {**source.record, "local_path": "changed.kt"}
            (Path(folder) / "changed.kt").write_text(source.text.replace("package ", "package changed.", 1))
            with patch.object(source_evidence, "ROOT", Path(folder)), self.assertRaisesRegex(ValueError, "SHA mismatch"):
                source_evidence.PinnedSource(record)


if __name__ == "__main__":
    unittest.main()
