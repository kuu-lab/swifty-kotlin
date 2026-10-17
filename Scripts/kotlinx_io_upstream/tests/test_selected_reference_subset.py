"""Focused tests for selected upstream reference method preparation."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
SPEC = importlib.util.spec_from_file_location("selected_reference_subset", ROOT / "run_selected_reference_subset.py")
runner = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(runner)


class SelectedReferenceSubsetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="kio-selected-reference-")
        self.root = Path(self.temporary.name)
        self.upstream = self.root / "upstream"
        self.output = self.root / "output"
        self.output.mkdir()
        self.source_path = "core/common/test/samples/samples.kt"
        self.raw = (
            "package sample\n\n"
            "class Suite {\n"
            "    @Test fun first() { assertEquals(1, 1) }\n"
            "    @Test fun second() { assertEquals(2, 2) }\n"
            "}\n"
        ).encode()
        self.source = self.upstream / self.source_path
        self.source.parent.mkdir(parents=True)
        self.source.write_bytes(self.raw)
        self.blob_sha = hashlib.sha1(b"blob " + str(len(self.raw)).encode() + b"\0" + self.raw).hexdigest()
        self.record = {
            "path": self.source_path,
            "sha256": hashlib.sha256(self.raw).hexdigest(),
            "git_blob_sha": self.blob_sha,
        }
        self.lock = {"upstream_files": [self.record]}
        self.rows = [self._row("first"), self._row("second")]

    def tearDown(self):
        self.temporary.cleanup()

    def _row(self, method):
        return {
            "execution_id": f"[engine:junit-jupiter]/[class:sample.Suite]/[method:{method}()]",
            "concrete_class": "sample.Suite",
            "declaring_class": "sample.Suite",
            "method_name": method,
            "parameter_types": "",
            "upstream_path": self.source_path,
            "git_blob_sha": self.blob_sha,
        }

    def test_selected_driver_preserves_original_file_and_only_calls_selected_methods(self):
        port = runner.prepare_selected_port(self.upstream, self.rows, self.lock, self.output)
        port_path = Path(port["port_path"])
        driver = Path(port["driver_path"]).read_text(encoding="utf-8")

        self.assertTrue(port["original_bytes_preserved_as_suffix"])
        self.assertEqual(port_path.read_bytes()[port["prefix_bytes"]:], self.raw)
        self.assertIn("Suite().first()", driver)
        self.assertIn("Suite().second()", driver)
        self.assertIn(self.rows[0]["execution_id"], driver)
        self.assertIn(self.rows[1]["execution_id"], driver)

    def test_rejects_parameterized_inherited_and_hooked_methods(self):
        parameterized = dict(self.rows[0], parameter_types="kotlin.Int")
        with self.assertRaisesRegex(ValueError, "direct parameterless"):
            runner.prepare_selected_port(self.upstream, [parameterized], self.lock, self.output)

        inherited = dict(self.rows[0], declaring_class="sample.Base")
        with self.assertRaisesRegex(ValueError, "direct parameterless"):
            runner.prepare_selected_port(self.upstream, [inherited], self.lock, self.output)

        hooked_source = self.raw.replace(b"class Suite {", b"class Suite {\n    @BeforeEach fun setup() {}")
        self.source.write_bytes(hooked_source)
        hooked_record = dict(self.record,
            sha256=hashlib.sha256(hooked_source).hexdigest(),
            git_blob_sha=hashlib.sha1(b"blob " + str(len(hooked_source)).encode() + b"\0" + hooked_source).hexdigest())
        with self.assertRaisesRegex(ValueError, "test hooks"):
            runner.prepare_selected_port(self.upstream, self.rows, {"upstream_files": [hooked_record]}, self.output)

    def test_reference_selection_keeps_only_requested_source_ids_and_all_expansions(self):
        catalog = [
            dict(self.rows[0], upstream_id="core/common/test/samples/samples.kt#first"),
            dict(self.rows[1], upstream_id="core/common/test/samples/samples.kt#second"),
            dict(self.rows[1], execution_id="another.expansion", upstream_id="core/common/test/samples/samples.kt#second"),
        ]
        selected = runner.reference_rows(
            "jvm", catalog,
            ["core/common/test/samples/samples.kt#second"],
        )
        self.assertEqual([row["execution_id"] for row in selected], [self.rows[1]["execution_id"], "another.expansion"])


if __name__ == "__main__":
    unittest.main()
