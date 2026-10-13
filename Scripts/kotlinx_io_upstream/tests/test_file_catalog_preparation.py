import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))
from prepare_candidate_catalog import prepare_catalog
from run_candidate_subset import PREFIX, parse_events
from run_jvm_reference import execute


class FileCatalogPreparationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.addCleanup(self.temporary.cleanup)
        # Locked originals are supplied explicitly by the existing harness, not downloaded by this test.
        upstream = os.environ.get("KSWIFTK_IO_UPSTREAM")
        if not upstream:
            self.skipTest("Set KSWIFTK_IO_UPSTREAM to the locked 0.9.1 checkout; no network or source fallback")
        self.upstream = Path(upstream)
        self.lock = json.loads((HERE / "reference-lock.json").read_text())
        self.catalog = json.loads((HERE / "native-executions.expected.json").read_text())
        self.declarations = json.loads((HERE / "candidate-declarations.json").read_text())
        self.closure = json.loads((HERE / "files/original-source-closure.linux.json").read_text())

    def prepare(self, closure):
        out = self.root / ("prepared-" + str(len(list(self.root.iterdir()))))
        out.mkdir()
        return prepare_catalog(self.upstream, self.catalog, self.lock, self.closure["suites"], out,
                               "linux", self.declarations, source_closure=closure)[0]

    def test_scoped_driver_matches_existing_driver_and_preserves_original_suffixes(self):
        scoped = self.prepare(self.closure)
        full = self.prepare(None)
        self.assertEqual(Path(scoped["driver_path"]).read_bytes(), Path(full["driver_path"]).read_bytes())
        self.assertEqual(30, len(scoped["execution_ids"]))
        self.assertEqual(4, len(scoped["source_ports"]))
        text = Path(scoped["driver_path"]).read_text()
        self.assertEqual(28, text.count("instance.cleanup()"))
        self.assertEqual(28, text.count("} finally {"))
        for item in scoped["original_sources"]:
            raw = (self.upstream / item["source_path"]).read_bytes()
            self.assertEqual(PREFIX + raw, Path(item["port_path"]).read_bytes())

    def test_old_upstream_pin_is_rejected(self):
        c = copy.deepcopy(self.closure); c["upstream_commit"] = "0" * 40
        with self.assertRaisesRegex(ValueError, "pinned target"): self.prepare(c)

    def test_closure_cannot_omit_selected_declaration(self):
        c = copy.deepcopy(self.closure); c["source_paths"].remove("core/common/test/files/SmokeFileTest.kt")
        with self.assertRaisesRegex(ValueError, "omit"): self.prepare(c)

    def test_closure_cannot_replace_selected_suites(self):
        c = copy.deepcopy(self.closure); c["suites"] = ["kotlinx.io.files.UtilsTest"]
        with self.assertRaisesRegex(ValueError, "selected suites"): self.prepare(c)

    def test_closure_cannot_claim_different_host(self):
        c = copy.deepcopy(self.closure); c["target"] = "macos"
        with self.assertRaisesRegex(ValueError, "pinned target"): self.prepare(c)

    def test_compile_only_or_missing_events_are_not_passes(self):
        port = self.prepare(self.closure)
        events = parse_events("", port["execution_ids"], port["event_token"])
        self.assertEqual(30, len(events))
        self.assertTrue(all(row["status"] == "NOT_RUN" for row in events))

    def test_owned_execution_directory_and_environment_are_recorded(self):
        work = self.root / "owned"; work.mkdir()
        output = self.root / "raw"; output.mkdir()
        code = execute([sys.executable, "-c", "import os;print(os.getcwd());print(os.environ['TMPDIR'])"],
                       output, "support-control", 10, {"TMPDIR": str(work)}, working_directory=work)
        self.assertEqual(0, code)
        self.assertEqual(str(work) + "\n" + str(work) + "\n", (output / "support-control.stdout").read_text())
        self.assertEqual(str(work), json.loads((output / "support-control.cwd.json").read_text()))


if __name__ == "__main__": unittest.main()
