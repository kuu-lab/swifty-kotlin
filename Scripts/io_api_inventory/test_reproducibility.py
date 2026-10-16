#!/usr/bin/env python3
"""Check that the ledger survives relocation and filesystem creation order."""

import importlib.util
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

    def test_relocated_checkout_with_reverse_creation_order_matches(self):
        original = load_generator(HERE / "generate.py")
        expected = rendered_outputs(original)
        with tempfile.TemporaryDirectory(prefix="io-inventory-relocated-") as temporary:
            relocated = Path(temporary) / "checkout"
            inputs = list(HERE.rglob("*"))
            inputs.extend((
                REPO / "Scripts/kotlinx_io_upstream/reference-lock.json",
                REPO / "Scripts/kotlinx_io_upstream/jvm-executions.expected.json",
                REPO / "Scripts/kotlinx_io_upstream/native-executions.expected.json",
            ))
            inputs.extend(
                REPO / reference.split("#", 1)[0]
                for probe in original.load_candidate_probe_catalog()
                for reference in probe["test_refs"]
                if reference.startswith(("Scripts/", "Tests/"))
            )
            inputs.extend((REPO / "Sources/CompilerCore/Stdlib/kotlinx/io").rglob("*.kt"))
            inputs.extend((REPO / "Sources/Runtime").rglob("*.swift"))
            test_inputs = list((REPO / "Tests").rglob("*.swift"))
            test_inputs.extend((REPO / "Tests/CompilerCoreTests/GoldenCases/Sema").glob("*.kt"))
            test_inputs.extend((REPO / "Scripts/diff_cases").glob("*.kt"))
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

    def test_exact_overload_exception_and_abi_mapping(self):
        declaration = self.row("kotlinx.io/readByteArray|readByteArray@kotlinx.io.Source(kotlin.Int){}")
        self.assertEqual(declaration["upstream_source_refs"], "core/common/src/Sources.kt:252")
        self.assertIn("EOFException", declaration["exception_contract"])
        self.assertIn("IllegalArgumentException", declaration["exception_contract"])
        refs = set(declaration["jvm_abi_refs"].split(";"))
        paired = [row for row in self.rows if row["row_id"] in refs]
        self.assertTrue(paired)
        self.assertTrue(all(row["_source_key"] == declaration["_source_key"] for row in paired))

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
