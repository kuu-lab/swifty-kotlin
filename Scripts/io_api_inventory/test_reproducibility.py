#!/usr/bin/env python3
"""Check that the ledger survives relocation and filesystem creation order."""

import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]


def load_generator(path):
    spec = importlib.util.spec_from_file_location("io_inventory_generator", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rendered_outputs(module):
    lock, rows, scopes = module.build_outputs()
    return (
        module.render_tsv(module.LEDGER_PATH, module.LEDGER_COLUMNS, rows),
        module.render_tsv(module.SCOPE_PATH, module.SCOPE_COLUMNS, scopes),
        module.make_summary(lock, rows, scopes),
    )


class ReproducibilityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generator = load_generator(HERE / "generate.py")
        cls.lock, cls.rows, cls.scopes = cls.generator.build_outputs()

    def row(self, api_id):
        return next(row for row in self.rows if row.get("_api_id") == api_id)

    def test_segment_data_probe_refs_are_limited_to_its_api(self):
        paths = sorted((HERE / "probes").glob("segment_data_as_byte_array*.kt"))
        probes = [(path.relative_to(REPO).as_posix(), path.read_text(encoding="utf-8")) for path in paths]
        target = {"_candidate_name": "dataAsByteArray", "owner_fqn": "kotlinx/io/Segment", "module": "core"}
        unrelated = {"_candidate_name": "read", "owner_fqn": "kotlinx/io/Source", "module": "core"}

        self.assertEqual(self.generator.local_test_refs(target, probes), [path for path, _ in probes])
        self.assertEqual(self.generator.local_test_refs(unrelated, probes), [])

    def test_relocated_checkout_with_reverse_creation_order_matches(self):
        original = load_generator(HERE / "generate.py")
        expected = rendered_outputs(original)
        with tempfile.TemporaryDirectory(prefix="io-inventory-relocated-") as temporary:
            relocated = Path(temporary) / "checkout"
            inputs = list(HERE.rglob("*"))
            inputs.extend((REPO / "Sources/CompilerCore/Stdlib/kotlinx/io").rglob("*.kt"))
            inputs.extend((REPO / "Sources/Runtime").rglob("*.swift"))
            test_inputs = list((REPO / "Tests").rglob("*.swift"))
            test_inputs.extend((REPO / "Tests/CompilerCoreTests/GoldenCases/Sema").glob("*.kt"))
            test_inputs.extend((REPO / "Scripts/diff_cases").glob("*.kt"))
            test_inputs.extend((REPO / "Tests/CompilerBackendTests/Fixtures/IOSegmentReadContextImpl2590").glob("*.kt"))
            inputs.extend(
                path for path in test_inputs
                if path.relative_to(REPO).as_posix().startswith(original.LOCAL_IO_TEST_PREFIXES)
            )
            for source in sorted(set(inputs), reverse=True):
                if not source.is_file() or "__pycache__" in source.parts:
                    continue
                destination = relocated / source.relative_to(REPO)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
            generator = relocated / "Scripts/io_api_inventory/generate.py"
            self.assertEqual(rendered_outputs(load_generator(generator)), expected)

    def test_source_array_inventory_links_existing_kotlin_regressions(self):
        declaration = self.row("kotlinx.io/readByteArray|readByteArray@kotlinx.io.Source(kotlin.Int){}")
        references = declaration["local_test_refs"].split(";")
        self.assertIn("Tests/CompilerCoreTests/GoldenCases/Sema/kotlinx_io_sources_surface.kt", references)
        self.assertIn("Scripts/diff_cases/kotlinx_io_sources_arrays.kt", references)

    def test_segment_read_context_probe_is_hashed_without_promoting_rows(self):
        row_ids = (
            "internal-230a62161c7ea51a",
            "jvm-f8c529b67df6423d",
            "klib-80388c3ba30d5f55",
            "klib-bc524370ccf4a2da",
        )
        for row_id in row_ids:
            row = next(row for row in self.rows if row["row_id"] == row_id)
            references = row["local_test_refs"].split(";")
            self.assertIn("Tests/CompilerBackendTests/Fixtures/IOSegmentReadContextImpl2590/Producer.kt", references)
            self.assertIn("Scripts/io_api_inventory/f02_consumers/SegmentReadContextAbiProbe.java", references)
            self.assertEqual(row["status"], "unverified")

        probe_refs = {
            "Tests/CompilerBackendTests/Fixtures/IOSegmentReadContextImpl2590/Producer.kt",
            "Scripts/io_api_inventory/f02_consumers/SegmentReadContextAbiProbe.java",
        }
        for row in self.rows:
            if row["row_id"] not in row_ids:
                self.assertFalse(probe_refs.intersection(row["local_test_refs"].split(";")))

    def test_exact_overload_exception_and_abi_mapping(self):
        declaration = self.row("kotlinx.io/readByteArray|readByteArray@kotlinx.io.Source(kotlin.Int){}")
        self.assertEqual(declaration["upstream_source_refs"], "core/common/src/Sources.kt:252")
        self.assertIn("EOFException", declaration["exception_contract"])
        self.assertIn("IllegalArgumentException", declaration["exception_contract"])
        refs = set(declaration["jvm_abi_refs"].split(";"))
        paired = [row for row in self.rows if row["row_id"] in refs]
        self.assertTrue(paired)
        self.assertTrue(all(row["_source_key"] == declaration["_source_key"] for row in paired))

    def test_deprecated_path_rows_do_not_claim_unrelated_upstream_assertions(self):
        rows = {row["row_id"]: row for row in self.rows}
        for row_id in (
            "jvm-23bdc46eecb769ad",
            "jvm-4a6ead57ff31eb51",
            "klib-91d3efd901de8c9b",
            "klib-ec16724d485f26fc",
        ):
            with self.subTest(row_id=row_id):
                row = rows[row_id]
                self.assertEqual(row["upstream_test_refs"], self.generator.NO_DIRECT_UPSTREAM_ASSERTION)
                self.assertEqual(row["status"], "unverified")
                self.assertIn("Scripts/diff_cases/kotlinx_io_file_legacy_suppressed.kt", row["local_test_refs"])
                self.assertIn("Tests/CompilerCoreTests/Sema/KotlinxIOF01ContractTests.swift", row["local_test_refs"])
                for unrelated_case in (
                    "core/common/test/files/SmokeFileTest.kt#createAnEmptyFileUsingSink",
                    "core/common/test/files/SmokeFileTest.kt#closeFileSinkTwice",
                    "core/common/test/files/SmokeFileTest.kt#closeFileSourceTwice",
                ):
                    self.assertFalse(self.generator._case_id_matches_row(row, unrelated_case))
    def test_kuu2633_default_bridges_link_exact_source_contracts(self):
        expected = {
            "jvm-29a01d1deaf3b966": "klib-8f2cd67956fefb8b",
            "jvm-32ddc189d171b174": "klib-b33ce5b385a93879",
            "jvm-5c5fb6c81ee3a3b9": "klib-001cc19c43da51fc",
            "jvm-b88878973d5558f7": "klib-5864c1c328005421",
        }
        self.assertEqual(self.generator.INDEX_OF_DEFAULT_BRIDGE_SOURCE_ROWS, expected)
        self.assertEqual(set(self.generator.INDEX_OF_DEFAULT_BRIDGE_UPSTREAM_TEST_REFS), set(expected))
        by_id = {row["row_id"]: row for row in self.rows}
        self.assertTrue(set(expected).issubset(by_id))
        test_index = json.loads((HERE / "upstream-tests-index.json").read_text(encoding="utf-8"))
        indexed_tests = {entry["path"]: set(entry.get("testNames", [])) for entry in test_index["files"]}
        index = self.generator.SourceIndex(HERE / "source-declarations.json", REPO, self.generator.UPSTREAM)
        upstream_obligations = json.loads(
            (REPO / "Scripts/kotlinx_io_upstream/jvm_interop/native-default-obligations.expected.json")
            .read_text(encoding="utf-8")
        )
        shapes = {row["rowID"]: row for row in upstream_obligations["rows"] if row["rowID"] in expected}

        for bridge_id, source_id in expected.items():
            with self.subTest(row_id=bridge_id):
                bridge = by_id[bridge_id]
                source = by_id[source_id]
                self.assertEqual(bridge["owner_issue"], "KUU-2633")
                self.assertEqual(bridge["status"], "unverified")
                self.assertEqual(bridge["local_candidate_refs"], source["local_candidate_refs"])
                self.assertEqual(bridge["local_implementation_refs"], source["local_implementation_refs"])
                upstream_refs = self.generator.INDEX_OF_DEFAULT_BRIDGE_UPSTREAM_TEST_REFS[bridge_id]
                self.assertEqual(tuple(bridge["upstream_test_refs"].split(";")), upstream_refs)
                for reference in upstream_refs:
                    path, method = reference.split("#", 1)
                    self.assertIn(method, indexed_tests[path], reference)
                if expected_shape_receiver := shapes[bridge_id]["extensionReceiverToken"]:
                    if expected_shape_receiver == "Lkotlinx.io.Buffer;":
                        self.assertFalse(any("AbstractSourceTest.kt" in ref for ref in upstream_refs))
                    else:
                        self.assertFalse(any("CommonBufferTest.kt" in ref for ref in upstream_refs))
                self.assertEqual(
                    set(bridge["local_test_refs"].split(";")),
                    set(self.generator.INDEX_OF_DEFAULT_BRIDGE_LOCAL_TEST_REFS),
                )
                self.assertIn(f"generated JVM $default bridge -> {source_id}", bridge["upstream_source_refs"])
                self.assertIn("separate from a physical JVM classfile ABI", bridge["notes"])

                expected_shape = shapes[bridge_id]
                upstream = index.match("upstream", source["_source_key"])
                local = index.match("local", source["_source_key"])
                self.assertEqual(len(upstream), 1)
                self.assertEqual(len(local), 1)
                reference = upstream[0]
                candidate = local[0]
                self.assertEqual(reference["visibility"], "public")
                self.assertEqual(candidate["visibility"], "public")
                self.assertEqual(
                    [parameter["default"] is not None for parameter in reference["parameters"]],
                    expected_shape["defaults"],
                )
                self.assertEqual(
                    [parameter["default"] is not None for parameter in candidate["parameters"]],
                    expected_shape["defaults"],
                )
                def normalized_defaults(declaration):
                    return {
                        parameter["name"]: (
                            parameter["default"][:-1]
                            if parameter["default"] and parameter["default"].endswith("L")
                            and parameter["default"][:-1].isdigit()
                            else parameter["default"]
                        )
                        for parameter in declaration["parameters"]
                        if parameter["default"] is not None
                    }

                self.assertEqual(normalized_defaults(reference), normalized_defaults(candidate))
                reference_metadata = self.generator.declaration_metadata(reference)
                candidate_metadata = self.generator.declaration_metadata(candidate)
                self.assertEqual(reference_metadata[0], candidate_metadata[0])
                self.assertEqual(reference_metadata[2], candidate_metadata[2])
                self.assertEqual(source["local_contract_differences"], "none detected (semantics unverified)")

    def test_apple_and_bytebuffer_do_not_match_other_receivers(self):
        index = self.generator.SourceIndex(HERE / "source-declarations.json", REPO, self.generator.UPSTREAM)
        for api_id in (
            "kotlinx.io.bytestring/toByteString|toByteString@platform.Foundation.NSData(){}",
            "kotlinx.io/asSource|asSource@platform.Foundation.NSInputStream(){}",
        ):
            row = self.row(api_id)
            matches = index.match("local", row["_source_key"])
            self.assertTrue(matches, "The integrated Apple implementation must match its exact receiver")
            exact_refs = {f"{declaration['path']}:{declaration['line']}" for declaration in matches}
            self.assertEqual(set(row["local_candidate_refs"].split(";")), exact_refs)
            self.assertEqual(row["status"], "unverified")
            self.assertEqual(row["owner_issue"], "KUU-1763")
            wrong_refs = {f"{declaration['path']}:{declaration['line']}"
                          for declaration in index.declarations if declaration["origin"] == "local"
                          and declaration["name"] == row["name"] and index.declaration_key(declaration) != row["_source_key"]}
            self.assertTrue(wrong_refs, "Keep same-name alternative receivers as negative controls")
            self.assertFalse(exact_refs & wrong_refs)
        row = next(row for row in self.rows if row.get("_source_key") == (
            "function", "kotlinx.io.readAtMostTo", "kotlinx.io.Source", ("java.nio.ByteBuffer",)
        ))
        matches = index.match("local", row["_source_key"])
        self.assertTrue(matches)
        self.assertEqual(set(row["local_candidate_refs"].split(";")),
                         {f"{declaration['path']}:{declaration['line']}" for declaration in matches})
        self.assertEqual(row["owner_issue"], "KUU-1762")

    def test_jvm_name_is_scoped_and_internal_visibility_is_preserved(self):
        row = next(row for row in self.rows if row["representation"] == "JVM public ABI dump"
                   and row["owner_fqn"] == "kotlinx/io/files/FileSystem" and row["name"] == "source")
        self.assertIn("files/FileSystem.kt:", row["local_candidate_refs"])
        self.assertEqual(row["_candidate_name"], "source")
        self.assertEqual(row["source_api"], "yes")
        row = self.row("kotlinx.io.bytestring/ByteString.getBackingArrayReference|getBackingArrayReference(){}")
        self.assertEqual(row["source_api"], "no")
        self.assertTrue(row["api_kind"].startswith("internal "))
        internals = [row for row in self.rows if row["representation"] == "@PublishedApi internal source declaration" and row["name"] == "sourceHack"]
        self.assertEqual(len(internals), 1)
        self.assertIn("Path.sourceHack", internals[0]["signature"])

    def test_field_annotations_alias_targets_and_accessor_roles(self):
        row = next(row for row in self.rows if row["representation"] == "JVM public ABI dump"
                   and row["name"] == "SystemFileSystem")
        self.assertEqual(row["api_kind"], "JVM field ABI")
        self.assertIn("JvmField", row["annotations"])
        aliases = [row for row in self.rows if row["representation"] == "Kotlin platform typealias"]
        self.assertEqual(len(aliases), 3)
        self.assertTrue(all("java.io." in row["signature"] and row["owner_issue"] == "KUU-1762" for row in aliases))
        setter = next(row for row in self.rows if "/ KLIB dump" in row["representation"] and ".<set-sizeMut>" in row["_api_id"])
        paired = [row for row in self.rows if row["row_id"] in setter["jvm_abi_refs"].split(";")]
        self.assertTrue(paired)
        self.assertTrue(all(row["_accessor_role"] == "setter" for row in paired))

    def test_byte_array_append_defaults_match_and_all_source_rows_are_mapped(self):
        row = next(
            row for row in self.rows
            if row["representation"] == "Kotlin source API / KLIB dump"
            and row["owner_fqn"] == "kotlinx.io.bytestring/ByteStringBuilder"
            and row["name"] == "append"
            and "kotlin/ByteArray" in row["signature"]
        )
        self.assertEqual(row["default_parameter_count"], "2")
        self.assertEqual(row["local_contract_differences"], "none detected (semantics unverified)")
        self.assertEqual(row["owner_issue"], "KUU-1760")
        for row in self.rows:
            if "/ KLIB dump" in row["representation"] or "_source_key" in row:
                self.assertNotIn("unmapped", row["upstream_source_refs"], row["_api_id"])

    def test_constructor_implementations_include_initializers_and_delegation(self):
        for name in ("ByteString", "ByteStringBuilder", "FileMetadata"):
            constructors = [row for row in self.rows
                            if row.get("_source_key", ())[:2] == (
                                "constructor", "kotlinx.io.%s%s.<init>" % (
                                    "files." if name == "FileMetadata" else "bytestring.", name))
                            and row["local_candidate_refs"] != "none"]
            self.assertTrue(constructors, name)
            self.assertTrue(all(row["local_implementation_refs"].startswith("Sources/")
                                for row in constructors), name)
        import json
        catalog = json.loads((HERE / "source-declarations.json").read_text())
        expect_constructors = [declaration for declaration in catalog["declarations"]
                               if declaration["kind"] == "constructor" and declaration["expect"]]
        self.assertTrue(expect_constructors)
        self.assertTrue(all(not declaration["hasBody"] for declaration in expect_constructors))


if __name__ == "__main__":
    unittest.main()
