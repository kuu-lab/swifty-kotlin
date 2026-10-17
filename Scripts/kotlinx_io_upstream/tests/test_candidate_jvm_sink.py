#!/usr/bin/env python3
"""Protect source-port identity and assertion preservation for the JVM Sink bridge."""

import hashlib
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "run_candidate_jvm_sink.py"
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location("kio_candidate_jvm_sink", SCRIPT)
RUNNER = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(RUNNER)


def locked_file(path: str, content: bytes) -> dict:
    return {
        "path": path,
        "sha256": hashlib.sha256(content).hexdigest(),
        "git_blob_sha": hashlib.sha1(b"blob " + str(len(content)).encode() + b"\0" + content).hexdigest(),
    }


class CandidateJvmSinkTests(unittest.TestCase):
    def test_port_changes_only_assertion_imports_and_preserves_test_body(self):
        source = (
            "package kotlinx.io\n"
            "import java.io.OutputStream\n"
            "import java.nio.ByteBuffer\n"
            "import java.nio.charset.Charset\n"
            "import kotlin.test.Test\n"
            "import kotlin.test.assertEquals\n"
            "import kotlin.test.assertFailsWith\n"
            "import kotlin.text.Charsets.UTF_8\n"
            "class BufferSinkTestJVM {\n"
            "    @Test fun outputStream() { assertEquals(7, sink.writeByte(7)) }\n"
            "}\n"
        ).encode()
        factory = b"package kotlinx.io\ninternal interface SinkFactory\n"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            upstream = root / "upstream"
            source_path = upstream / RUNNER.SOURCE_PATH
            factory_path = upstream / RUNNER.FACTORY_PATH
            source_path.parent.mkdir(parents=True)
            factory_path.parent.mkdir(parents=True)
            source_path.write_bytes(source)
            factory_path.write_bytes(factory)
            output = root / "output"
            output.mkdir()
            selected = [{
                "execution_id": "[engine:kswiftk-macos-native]/[class:kotlinx.io.BufferSinkTestJVM]/[method:outputStream()]",
                "reference_execution_id": "[engine:junit-jupiter]/[class:kotlinx.io.BufferSinkTestJVM]/[method:outputStream()]",
                "concrete_class": "kotlinx.io.BufferSinkTestJVM",
                "method_name": "outputStream",
            }]
            result = RUNNER.prepare_port(upstream, selected, {
                "upstream_files": [
                    locked_file(RUNNER.SOURCE_PATH, source),
                    locked_file(RUNNER.FACTORY_PATH, factory),
                ],
            }, output)
            ported = (output / "AbstractSinkTestJVM.kt").read_bytes()[len(RUNNER.PREFIX):]
            restored = ported.decode()
            for original, replacement in RUNNER.IMPORT_REWRITES.items():
                restored = restored.replace(replacement, original)
            self.assertEqual(restored.encode(), source)
            self.assertTrue(result["assertion_bodies_unchanged"])
            self.assertEqual(result["ported_contract_probe_sha256"], result["contract_probe_source_sha256"])
            driver = Path(result["driver_path"]).read_text()
            self.assertIn("SinkTestObservations.reset()", driver)
            self.assertIn("kotlinx.io.BufferSinkTestJVM().outputStream()", driver)
            self.assertIn("verifySinkWriteStringContracts()", driver)


if __name__ == "__main__":
    unittest.main()
