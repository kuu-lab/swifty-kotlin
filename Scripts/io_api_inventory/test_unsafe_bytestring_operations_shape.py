#!/usr/bin/env python3
"""Pin the UnsafeByteStringOperations object and JVM singleton declarations."""

import csv
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = ROOT / "Scripts/io_api_inventory/upstream/kotlinx-io-0.9.1/bytestring"
SOURCE = ROOT / "Sources/CompilerCore/Stdlib/kotlinx/io/bytestring/unsafe/UnsafeByteStringOperations.kt"
INVENTORY = ROOT / "Scripts/io_api_inventory/api-inventory.tsv"
DECLARATIONS = ROOT / "Scripts/io_api_inventory/source-declarations.json"


class UnsafeByteStringOperationsShapeTests(unittest.TestCase):
    def test_pinned_source_and_klib_declare_the_public_marked_object(self):
        source = (UPSTREAM / "common/src/unsafe/UnsafeByteStringOperations.kt").read_text(encoding="utf-8")
        candidate = SOURCE.read_text(encoding="utf-8")
        klib_api = (UPSTREAM / "api/kotlinx-io-bytestring.klib.api").read_text(encoding="utf-8")
        declaration = "final object kotlinx.io.bytestring.unsafe/UnsafeByteStringOperations {"

        self.assertIn("@UnsafeByteStringApi\n@OptIn(ExperimentalContracts::class)\npublic object UnsafeByteStringOperations {", source)
        self.assertIn("@UnsafeByteStringApi\n@OptIn(ExperimentalContracts::class)\npublic object UnsafeByteStringOperations {", candidate)
        self.assertIn(declaration, klib_api)

        declarations = json.loads(DECLARATIONS.read_text(encoding="utf-8"))
        candidates = [entry for entry in declarations["declarations"] if
                      entry.get("path") == "Sources/CompilerCore/Stdlib/kotlinx/io/bytestring/unsafe/UnsafeByteStringOperations.kt"
                      and entry.get("fqName") == "kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations"]
        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0]["kind"], "object")
        self.assertEqual(candidates[0]["visibility"], "public")
        self.assertTrue(any(annotation["name"] == "UnsafeByteStringApi"
                            for annotation in candidates[0]["annotations"]))

    def test_pinned_jvm_dump_has_exact_public_static_final_singleton_field(self):
        api = (UPSTREAM / "api/kotlinx-io-bytestring.api").read_text(encoding="utf-8")
        lines = api.splitlines()
        owner = "public final class kotlinx/io/bytestring/unsafe/UnsafeByteStringOperations {"
        field = "\tpublic static final field INSTANCE Lkotlinx/io/bytestring/unsafe/UnsafeByteStringOperations;"

        self.assertEqual(lines.count(owner), 1)
        self.assertEqual(lines.count(field), 1)
        self.assertLess(lines.index(owner), lines.index(field))

    def test_inventory_keeps_the_three_object_shape_rows_and_their_pairing(self):
        with INVENTORY.open(encoding="utf-8", newline="") as stream:
            rows = {row["row_id"]: row for row in csv.DictReader(stream, delimiter="\t")}

        jvm_object = rows["jvm-16874beea5466602"]
        jvm_field = rows["jvm-1aae98343452a402"]
        klib_object = rows["klib-f6cdd7b8ec302161"]
        self.assertEqual(jvm_object["signature"], "public final class kotlinx/io/bytestring/unsafe/UnsafeByteStringOperations {")
        self.assertEqual(jvm_object["jvm_abi_refs"], "klib-f6cdd7b8ec302161")
        self.assertEqual(jvm_field["signature"], "public static final field INSTANCE Lkotlinx/io/bytestring/unsafe/UnsafeByteStringOperations;")
        self.assertEqual(jvm_field["jvm_abi_refs"], "klib-f6cdd7b8ec302161")
        self.assertEqual(klib_object["signature"], "final object kotlinx.io.bytestring.unsafe/UnsafeByteStringOperations {")
        self.assertEqual(set(klib_object["jvm_abi_refs"].split(";")), {
            "jvm-16874beea5466602", "jvm-1aae98343452a402",
        })


if __name__ == "__main__":
    unittest.main()
