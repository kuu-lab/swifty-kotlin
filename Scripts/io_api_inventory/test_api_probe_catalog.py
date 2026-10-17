#!/usr/bin/env python3
"""Check registered API probes are row-specific and cover each evidence lane."""

import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
UPSTREAM = HERE / "upstream/kotlinx-io-0.9.1"


def load_generator():
    spec = importlib.util.spec_from_file_location("io_inventory_generator", HERE / "generate.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_probe_runner():
    spec = importlib.util.spec_from_file_location("io_api_probe_runner", HERE / "run_api_probes.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class APIProbeCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generator = load_generator()
        cls.runner = load_probe_runner()
        cls.catalog = cls.generator.load_api_probe_catalog()
        with (HERE / "api-inventory.tsv").open(encoding="utf-8", newline="") as stream:
            cls.rows = {row["row_id"]: row for row in csv.DictReader(stream, delimiter="\t")}

    def test_registered_probes_cover_the_exact_row_lanes(self):
        execution_catalogs = self.generator._load_validation_execution_catalogs()
        for probe in self.catalog["probes"]:
            with self.subTest(row_id=probe["row_id"]):
                row = self.rows[probe["row_id"]]
                obligations = self.generator.validation_obligations(row)
                expected_lanes = self.generator.required_execution_lanes(obligations)
                self.assertEqual(set(probe["lanes"]), set(expected_lanes))
                self.assertTrue(self.generator._case_id_matches_row(row, probe["case_id"]))
                self.assertIn("#suite-reference", row["upstream_test_refs"])
                for lane, subjects in probe["lanes"].items():
                    for subject in ("reference", "candidate"):
                        self.assertEqual(execution_catalogs[subject][subjects[subject]], probe["case_id"])

    def test_probe_inputs_are_present_in_the_row_local_test_refs(self):
        for probe in self.catalog["probes"]:
            with self.subTest(row_id=probe["row_id"]):
                row = self.rows[probe["row_id"]]
                refs = set(row["local_test_refs"].split(";"))
                self.assertTrue(set(probe["probe_paths"]).issubset(refs))

    def test_hashes_cover_upstream_assertion_and_probe_inputs(self):
        for probe in self.catalog["probes"]:
            with self.subTest(row_id=probe["row_id"]):
                row = self.rows[probe["row_id"]]
                files = {}
                for reference in row["local_test_refs"].split(";"):
                    relative = reference.split("#", 1)[0]
                    path = REPO / relative
                    files[f"repo/{relative}"] = hashlib.sha256(path.read_bytes()).hexdigest()
                for reference in row["upstream_test_refs"].split(";"):
                    relative = reference.split("#", 1)[0]
                    path = UPSTREAM / relative
                    if path.is_file():
                        files[f"upstream/{relative}"] = hashlib.sha256(path.read_bytes()).hexdigest()
                    else:
                        lock = json.loads(self.generator.LOCK_PATH.read_text(encoding="utf-8"))
                        entry = next(item for item in lock["upstreamTests"] if item["path"] == relative)
                        descriptor = json.dumps(
                            {"gitBlobSha": entry["gitBlobSha"], "size": entry["size"]},
                            sort_keys=True, separators=(",", ":"),
                        )
                        files[f"upstream/{relative}"] = hashlib.sha256(descriptor.encode("utf-8")).hexdigest()
                for relative in probe["upstream_reference_paths"]:
                    path = UPSTREAM / relative
                    files[f"upstream/{relative}"] = hashlib.sha256(path.read_bytes()).hexdigest()
                catalog = REPO / "Scripts/io_api_inventory/api-probe-catalog.json"
                files["repo/Scripts/io_api_inventory/api-probe-catalog.json"] = hashlib.sha256(
                    catalog.read_bytes()
                ).hexdigest()
                expected = hashlib.sha256(json.dumps(
                    files, ensure_ascii=False, sort_keys=True, separators=(",", ":")
                ).encode("utf-8")).hexdigest()
                actual = self.generator.validation_input_hashes(row)["test_input_sha256"]
                self.assertEqual(actual, expected)

    def test_raw_run_requires_passing_fresh_compiler_and_stdlib_builds(self):
        compiler = str((REPO / ".build/debug/kswiftc").resolve())
        valid_run = {
            "candidate_compiler_build": self._build_stage(
                "candidate-compiler-build", ["swift", "build", "--product", "kswiftc"]
            ),
            "fresh_stdlib_build": self._build_stage(
                "candidate-fresh-stdlib",
                [compiler, "--stdlib-only", "--no-incremental", "-o", "/tmp/KSwiftKStdlib.kklib"],
            ),
        }
        sha256_pattern = self.generator.re.compile(r"^[0-9a-f]{64}$")
        self.generator.validate_api_probe_build_stages(valid_run, sha256_pattern)

        invalid_runs = []
        missing = json.loads(json.dumps(valid_run))
        del missing["candidate_compiler_build"]
        invalid_runs.append(missing)
        failed = json.loads(json.dumps(valid_run))
        failed["fresh_stdlib_build"]["status"] = "FAIL"
        invalid_runs.append(failed)
        wrong_compiler_command = json.loads(json.dumps(valid_run))
        wrong_compiler_command["candidate_compiler_build"]["command"] = ["swift", "build"]
        invalid_runs.append(wrong_compiler_command)
        wrong_stdlib_command = json.loads(json.dumps(valid_run))
        wrong_stdlib_command["fresh_stdlib_build"]["command"][2] = "--incremental"
        invalid_runs.append(wrong_stdlib_command)
        stale_output_hash = json.loads(json.dumps(valid_run))
        stale_output_hash["candidate_compiler_build"]["stdout"] = "tampered\n"
        invalid_runs.append(stale_output_hash)
        for run in invalid_runs:
            with self.subTest(run=run):
                with self.assertRaises(SystemExit):
                    self.generator.validate_api_probe_build_stages(run, sha256_pattern)

    def test_reference_final_class_diagnostic_uses_pinned_kotlinc_wording(self):
        diagnostic = "this type is final, so it cannot be extended."
        self.assertEqual(
            self.runner.validate_final_class_diagnostic(diagnostic, "kotlinc"),
            ("this type is final", "cannot be extended"),
        )
        with self.assertRaisesRegex(RuntimeError, "final-class rejection"):
            self.runner.validate_final_class_diagnostic(
                "class is final and cannot be inherited", "kotlinc"
            )

    def test_candidate_final_class_diagnostic_requires_issue_and_symbol(self):
        self.assertEqual(
            self.runner.validate_final_class_diagnostic(
                "error KSWIFTK-SEMA-FINAL: kotlinx.io.bytestring.ByteStringBuilder is final",
                "kswiftc",
            ),
            ("KSWIFTK-SEMA-FINAL", "kotlinx.io.bytestring.ByteStringBuilder"),
        )

    @staticmethod
    def _build_stage(stage_name, command):
        stdout = f"{stage_name} output\n"
        stderr = ""
        return {
            "stage": stage_name,
            "status": "PASS",
            "command": command,
            "exit_code": 0,
            "expected_exit_code": 0,
            "stdout": stdout,
            "stdout_sha256": hashlib.sha256(stdout.encode("utf-8")).hexdigest(),
            "stderr": stderr,
            "stderr_sha256": hashlib.sha256(stderr.encode("utf-8")).hexdigest(),
        }


if __name__ == "__main__":
    unittest.main()
