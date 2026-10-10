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
