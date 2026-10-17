#!/usr/bin/env python3
"""Guard source identity and distinguish reference coverage from paired PASS."""
import importlib.util
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "run_jvm_reference.py"
SPEC = importlib.util.spec_from_file_location("kio_jvm_reference", SCRIPT)
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class JvmReferenceTests(unittest.TestCase):
    def test_source_function_selection_expands_all_factory_executions(self):
        catalog = [
            {"upstream_id": "core/jvm/test/AbstractSourceTestJVM.kt#inputStream",
             "execution_id": f"[class:{suite}]/[method:inputStream()]", "source_set": "jvm",
             "upstream_path": "core/jvm/test/AbstractSourceTestJVM.kt"}
            for suite in ("kotlinx.io.BufferSourceTestJVM", "kotlinx.io.RealBufferedSourceTestJVM")
        ]
        selected = RUNNER.select_source_function_rows(
            catalog, ["core/jvm/test/AbstractSourceTestJVM.kt#inputStream"]
        )
        self.assertEqual([row["execution_id"] for row in selected], [row["execution_id"] for row in catalog])

    def test_source_function_selection_rejects_unknown_duplicate_and_empty_ids(self):
        catalog = [{"upstream_id": "core/jvm/test/Test.kt#read", "execution_id": "jvm.read",
                    "source_set": "jvm", "upstream_path": "core/jvm/test/Test.kt"}]
        for requested, message in (
            (["core/jvm/test/Test.kt#missing"], "unknown upstream source function ID"),
            (["core/jvm/test/Test.kt#read"] * 2, "must be unique"),
            ([""], "must be nonempty"),
        ):
            with self.subTest(requested=requested), self.assertRaisesRegex(ValueError, message):
                RUNNER.select_source_function_rows(catalog, requested)

    def test_source_function_without_jvm_execution_is_rejected(self):
        catalog = [{"upstream_id": "core/native/test/Test.kt#read", "execution_id": "native.read",
                    "source_set": "native", "upstream_path": "core/native/test/Test.kt"}]
        with self.assertRaisesRegex(ValueError, "no JVM execution"):
            RUNNER.select_source_function_rows(catalog, ["core/native/test/Test.kt#read"])

    def test_targeted_compile_closure_must_be_locked_unique_and_include_selected_test_source(self):
        pool = ["core/common/test/SourceFactory.kt", "core/jvm/test/AbstractSourceTestJVM.kt",
                "core/jvm/test/utilJVM.kt"]
        selected = RUNNER.resolve_compile_sources(
            pool, [pool[1], pool[0]], {"core/jvm/test/AbstractSourceTestJVM.kt"})
        self.assertEqual(selected, sorted([pool[0], pool[1]]))
        with self.assertRaisesRegex(ValueError, "unique"):
            RUNNER.resolve_compile_sources(pool, [pool[1], pool[1]], {pool[1]})
        with self.assertRaisesRegex(ValueError, "outside the locked"):
            RUNNER.resolve_compile_sources(pool, ["../unlocked.kt", pool[1]], {pool[1]})
        with self.assertRaisesRegex(ValueError, "omit selected test sources"):
            RUNNER.resolve_compile_sources(pool, [pool[0]], {pool[1]})

    def test_inherited_factory_executions_remain_distinct_and_candidate_unmapped(self):
        source = {"upstream_id": "core/common/test/Source.kt#read",
            "upstream_path": "core/common/test/Source.kt", "platform": "common",
            "upstream_metadata": {"git_blob_sha": "pinned"}}
        discovered = [{"execution_id": name, "concrete_class": name,
            "declaring_class": "io.AbstractSource", "method_name": "read"}
            for name in ("io.BufferSource", "io.PeekSource")]
        results = [{"execution_id": row["execution_id"], "status": "PASS"} for row in discovered]
        mapped = RUNNER.map_executions(discovered, results, {("io.AbstractSource", "read"): [source]}, discovered)
        self.assertEqual(len(mapped), 2)
        self.assertEqual({row["upstream_id"] for row in mapped}, {source["upstream_id"]})
        self.assertEqual({row["candidate_disposition"] for row in mapped}, {"unmapped"})
        self.assertEqual({row["concrete_class"] for row in mapped}, {"io.BufferSource", "io.PeekSource"})

    def test_missing_execution_and_container_failure_cannot_look_passed(self):
        source = {"upstream_id": "Source.kt#read", "upstream_path": "Source.kt", "platform": "common",
            "upstream_metadata": {"git_blob_sha": "pinned"}}
        test = {"execution_id": "read", "declaring_class": "Source", "method_name": "read"}
        lookup = {("Source", "read"): [source]}
        mapped = RUNNER.map_executions([test], [], lookup, [test])
        self.assertEqual(mapped[0]["reference_result"]["status"], "NOT_RUN")
        with self.assertRaisesRegex(ValueError, "failed containers"):
            RUNNER.map_executions([test], [{"execution_id": "container", "status": "CONTAINER_ERROR"}], lookup, [test])
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            RUNNER.map_executions([test], [], {("Source", "read"): [source, source]}, [test])
        with self.assertRaisesRegex(ValueError, "unmapped concrete"):
            RUNNER.map_executions([test], [], {}, [test])

    def test_factory_or_method_missing_from_discovery_is_rejected(self):
        tests = [{"execution_id": "Buffer#read"}, {"execution_id": "Peek#read"}]
        with self.assertRaisesRegex(ValueError, "NOT_DISCOVERED=1"):
            RUNNER.map_executions(tests[:1], [], {}, tests)

    def test_modified_upstream_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Test.kt"
            path.write_text("unchanged upstream assertion")
            record = {"sha256": RUNNER.sha256(path)}
            RUNNER.verify_file(path, record)
            path.write_text("removed assertion")
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                RUNNER.verify_file(path, record)


if __name__ == "__main__":
    unittest.main()
