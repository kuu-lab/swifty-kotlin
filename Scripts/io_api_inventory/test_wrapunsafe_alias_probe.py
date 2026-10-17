#!/usr/bin/env python3
"""Guard the dedicated wrapUnsafe alias probe and its row/lane boundaries."""

import csv
import importlib.util
import json
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PROBE_DIR = HERE / "wrapunsafe_alias"
CASE_ID = "Scripts/io_api_inventory/wrapunsafe_alias/Probe.kt#wrapUnsafeByteArrayAlias"
TARGET_ROW_IDS = {"jvm-f537e57626234f77", "klib-07506d12f1446693"}


def load_generator():
    spec = importlib.util.spec_from_file_location("io_inventory_generator", HERE / "generate.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load API inventory generator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_script(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class WrapUnsafeAliasProbeTests(unittest.TestCase):
    def test_manifest_registers_only_the_two_wrapunsafe_rows(self):
        manifest = json.loads((PROBE_DIR / "probe-manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(len(manifest["probes"]), 1)
        probe = manifest["probes"][0]
        self.assertEqual(probe["case_id"], CASE_ID)
        self.assertEqual(set(probe["row_ids"]), TARGET_ROW_IDS)
        self.assertEqual(probe["api_call"], "wrapUnsafe")
        source = (PROBE_DIR / "Probe.kt").read_text(encoding="utf-8")
        self.assertIn("UnsafeByteStringOperations.wrapUnsafe(input)", source)
        self.assertIn("input[0] = 0x7f", source)
        self.assertIn("wrapped[0]", source)
        self.assertIn("ByteString(input)", source)

    def test_generator_accepts_the_explicit_wrapunsafe_case(self):
        probe = load_generator()._load_validation_probe_manifest()[CASE_ID]
        self.assertEqual(probe["api_call"], "wrapUnsafe")
        self.assertEqual(set(probe["row_ids"]), TARGET_ROW_IDS)
        self.assertEqual(probe["receipt_ref"], "Scripts/io_api_inventory/wrapunsafe_alias/execution-catalog.json")

    def test_issue_rows_keep_distinct_jvm_and_klib_lane_obligations(self):
        generator = load_generator()
        with (HERE / "api-inventory.tsv").open(encoding="utf-8", newline="") as stream:
            rows = {row["row_id"]: row for row in csv.DictReader(stream, delimiter="\t")
                    if row["row_id"] in TARGET_ROW_IDS}
        self.assertEqual(set(rows), TARGET_ROW_IDS)
        self.assertEqual(generator.required_execution_lanes(generator.validation_obligations(rows["jvm-f537e57626234f77"])),
                         ["jvm-descriptor"])
        self.assertEqual(generator.required_execution_lanes(generator.validation_obligations(rows["klib-07506d12f1446693"])),
                         ["source-O0", "source-O2", "stdlib-library-O0", "stdlib-library-O2",
                          "producer-consumer-O0", "producer-consumer-O2", "apple-native-O0", "apple-native-O2"])

    def test_apple_native_reference_wins_over_generic_jvm_reference(self):
        executions = [
            {"execution_id": "jvm", "side": "reference", "lane": "*"},
            {"execution_id": "apple-native", "side": "reference", "lane": "apple-native-O0"},
        ]
        for name, path in (
            ("wrapunsafe_probe", HERE / "run_wrapunsafe_alias_probe.py"),
            ("backing_array_probe", HERE / "run_bytestring_backing_array_probe.py"),
        ):
            with self.subTest(runner=name):
                runner = load_script(name, path)
                self.assertEqual(runner.reference_execution_for_lane(executions, "apple-native-O0")["execution_id"],
                                 "apple-native")
                self.assertEqual(runner.reference_execution_for_lane(executions, "source-O0")["execution_id"], "jvm")


if __name__ == "__main__":
    unittest.main()
