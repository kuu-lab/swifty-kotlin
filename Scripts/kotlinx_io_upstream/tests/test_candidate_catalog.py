import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_candidate_catalog import prepare_catalog
from run_candidate_subset import PREFIX, parse_events


class CandidateCatalogTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.source_path = "core/common/test/FactoryTest.kt"
        raw = ("package sample\nabstract class Base { fun original() {} }\n"
               "class First : Base()\nclass Second : Base()\n").encode()
        source = self.root / self.source_path
        source.parent.mkdir(parents=True)
        source.write_bytes(raw)
        self.record = {"path": self.source_path, "sha256": hashlib.sha256(raw).hexdigest(),
                       "git_blob_sha": hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()}
        self.lock = {"commit": "pinned", "native_execution_catalog_sha256": "catalog", "upstream_files": [self.record]}
        self.rows = [{"concrete_class": "sample." + name, "declaring_class": "sample.Base",
                      "execution_id": "sample." + name + ".original", "method_name": "original",
                      "parameter_types": "", "upstream_path": self.source_path,
                      "upstream_id": self.source_path + "#original", "source_set": "common",
                      "git_blob_sha": self.record["git_blob_sha"]} for name in ["First", "Second"]]
        self.index = {"schema_version": 1, "upstream_commit": "pinned", "native_execution_catalog_sha256": "catalog",
                      "source_closures": {"linux": [self.source_path]}, "lifecycle_policy": "Native finally",
                      "classes": [{"concrete_class": "sample." + name, "source_path": self.source_path,
                                   "class_declaration_line": line, "declaration": "class " + name + " : Base()",
                                   "source_sha256": self.record["sha256"], "git_blob_sha": self.record["git_blob_sha"],
                                   "declaring_classes": ["sample.Base"], "execution_count": 1,
                                   "hook_methods": []} for name, line in [("First", 3), ("Second", 4)]]}

    def prepare(self, suites=None):
        output = self.root / "output"
        output.mkdir()
        return prepare_catalog(self.root, self.rows, self.lock, suites, output, "linux", self.index)[0]

    def test_factory_instances_and_source_function_ids_are_not_collapsed(self):
        port = self.prepare()
        self.assertEqual(len(port["source_ports"]), 1)
        self.assertEqual(Path(port["source_ports"][0]).read_bytes(), PREFIX + (self.root / self.source_path).read_bytes())
        self.assertEqual(len(port["execution_ids"]), 2)
        self.assertEqual(len(port["source_function_ids"]), 1)
        driver = Path(port["driver_path"]).read_text()
        self.assertIn("sample.First().original()", driver)
        self.assertIn("sample.Second().original()", driver)
        self.assertNotIn("sample.Base()", driver)

    def test_failure_and_unfinished_factory_are_retained(self):
        port = self.prepare()
        first, second = port["execution_ids"]
        token = port["event_token"]
        events = f"{token} BEGIN {first}\n{token} FAIL {first}\n{token} EXCEPTION sample.Failure\n{token} BEGIN {second}\n"
        results = parse_events(events, port["execution_ids"], token)
        self.assertEqual([row["status"] for row in results], ["FAIL", "NOT_FINISHED"])
        self.assertEqual(results[0]["exception_type"], "sample.Failure")

    def test_catalog_class_or_factory_expansion_mismatch_is_rejected(self):
        self.index["classes"][0]["execution_count"] = 2
        with self.assertRaisesRegex(ValueError, "factory expansion"):
            self.prepare()

    def test_changed_constructor_declaration_is_rejected(self):
        self.index["classes"][0]["declaration"] = "class First : Base(OTHER)"
        with self.assertRaisesRegex(ValueError, "declaration changed"):
            self.prepare()

    def test_parameterized_methods_require_a_new_audit(self):
        self.rows[0]["parameter_types"] = "Int"
        with self.assertRaisesRegex(ValueError, "parameterized"):
            self.prepare()

    def test_lifecycle_driver_preserves_lazy_instance_finally_and_terminal_order(self):
        path = "core/common/test/files/SmokeFileTest.kt"
        raw = b"package kotlinx.io.files\nclass SmokeFileTest {\n@Test fun original() {}\n@AfterTest fun cleanup() {}\n}\n"
        source = self.root / path
        source.parent.mkdir(parents=True)
        source.write_bytes(raw)
        record = {"path": path, "sha256": hashlib.sha256(raw).hexdigest(),
                  "git_blob_sha": hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()}
        self.lock["upstream_files"] = [record]
        row = copy.deepcopy(self.rows[0])
        suite = "kotlinx.io.files.SmokeFileTest"
        row.update(concrete_class=suite, declaring_class=suite, execution_id=suite + ".original",
                   upstream_path=path, upstream_id=path + "#original", git_blob_sha=record["git_blob_sha"])
        self.rows = [row]
        self.index["source_closures"]["linux"] = [path]
        self.index["classes"] = [{"concrete_class": suite, "source_path": path, "class_declaration_line": 2,
                                  "declaration": "class SmokeFileTest {", "source_sha256": record["sha256"],
                                  "git_blob_sha": record["git_blob_sha"], "declaring_classes": [suite],
                                  "execution_count": 1, "hook_methods": ["cleanup"]}]
        port = self.prepare()
        driver = Path(port["driver_path"]).read_text()
        self.assertIn("val instance by lazy { kotlinx.io.files.SmokeFileTest() }", driver)
        self.assertLess(driver.index("instance.original()"), driver.index("} finally {"))
        self.assertLess(driver.index("instance.cleanup()"), driver.index(" PASS "))
        self.assertLess(driver.index(" PASS "), driver.index("catch (failure: Throwable)"))
        # Removing a required hook from the declaration index must not silently
        # turn the unchanged upstream lifecycle into a hook-free PASS driver.
        self.index["classes"][0]["hook_methods"] = []
        other = self.root / "omitted-hook-output"
        other.mkdir()
        with self.assertRaisesRegex(ValueError, "lifecycle hook"):
            prepare_catalog(self.root, self.rows, self.lock, None, other, "linux", self.index)


if __name__ == "__main__":
    unittest.main()
