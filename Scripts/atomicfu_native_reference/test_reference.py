"""Integrity and outcome boundaries, independent of expensive Native execution."""

import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("reference", Path(__file__).with_name("reference.py"))
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


class ReferenceIntegrityTests(unittest.TestCase):
    def test_checked_in_fixtures_match_lock(self):
        lock = reference.load_lock()
        self.assertEqual(lock["target"], "linux_x64")
        self.assertEqual(lock["kotlin_version"], "2.3.10")

    def test_corrupt_cached_artifact_is_rejected_without_refetch(self):
        lock = {"artifacts": [{"role": "probe", "filename": "probe.klib", "size": 3,
                               "sha256": "0" * 64, "url": "https://example.invalid/probe.klib"}]}
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            (cache / "probe.klib").write_bytes(b"bad")
            with patch.object(reference.urllib.request, "urlopen", side_effect=AssertionError("must not fetch")):
                with self.assertRaises(reference.ReferenceFailure) as caught:
                    reference.cached_artifacts(lock, cache, True)
            self.assertEqual(caught.exception.status, "ERROR")

    def test_missing_offline_artifact_is_unsupported(self):
        lock = {"artifacts": [{"role": "probe", "filename": "probe.klib"}]}
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(reference.ReferenceFailure) as caught:
                reference.cached_artifacts(lock, Path(directory), False)
        self.assertEqual(caught.exception.status, "UNSUPPORTED")
        self.assertEqual(reference.EXIT_CODES[caught.exception.status], 77)

    def test_unsupported_host_does_not_execute_or_pass(self):
        with patch.object(reference.platform, "system", return_value="Darwin"):
            with self.assertRaises(reference.ReferenceFailure) as caught:
                reference.run_reference(None, {}, None, {})
        self.assertEqual(caught.exception.status, "UNSUPPORTED")

    def test_archive_paths_cannot_escape_installation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive_path = root / "unsafe.tar.gz"
            with tarfile.open(archive_path, "w:gz") as archive:
                member = tarfile.TarInfo("package/../../escaped")
                member.size = 1
                archive.addfile(member, io.BytesIO(b"x"))
            with self.assertRaises(reference.ReferenceFailure):
                reference.extract_archive(archive_path, root, "package")
            self.assertFalse((root.parent / "escaped").exists())

    def test_stderr_and_stdout_mismatch_are_differences(self):
        expected = (reference.ROOT / "native.expected").read_bytes()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "probe.stdout").write_bytes(expected)
            (output / "probe.stderr").write_bytes(b"unexpected\n")
            with self.assertRaises(reference.ReferenceFailure) as caught:
                reference.verify_result(output, "probe", "native.expected")
            self.assertEqual(caught.exception.status, "DIFFERENCE")
            (output / "probe.stderr").write_bytes(b"")
            (output / "probe.stdout").write_bytes(expected + b"extra\n")
            with self.assertRaises(reference.ReferenceFailure) as caught:
                reference.verify_result(output, "probe", "native.expected")
            self.assertEqual(caught.exception.status, "DIFFERENCE")

    def test_process_failure_retains_exit_code_and_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            with self.assertRaises(reference.ReferenceFailure) as caught:
                reference.execute([reference.sys.executable, "-c", "import sys; print('failed', file=sys.stderr); sys.exit(7)"],
                                  output, "failed", 5)
            self.assertEqual(caught.exception.status, "ERROR")
            self.assertEqual(caught.exception.execution["exit_code"], 7)
            self.assertEqual((output / "failed.stderr").read_text(), "failed\n")

    def test_optional_jvm_artifact_is_not_required_for_native(self):
        lock = {"artifacts": [{"role": "atomicfu_jvm", "filename": "absent.jar"}]}
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(reference.cached_artifacts(lock, Path(directory), False, {"native_compiler"}), {})

    def test_timeout_stops_launcher_descendants(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            marker = output / "descendant-was-left-running"
            script = ("import os,time,pathlib; pid=os.fork(); "
                      "time.sleep(0.3 if pid == 0 else 5); "
                      "pathlib.Path(" + repr(str(marker)) + ").write_text('still running')")
            with self.assertRaises(reference.ReferenceFailure) as caught:
                reference.execute([reference.sys.executable, "-c", script], output, "timeout", 0.1)
            self.assertEqual(caught.exception.status, "TIMEOUT")
            self.assertEqual(reference.EXIT_CODES[caught.exception.status], 124)
            time.sleep(0.4)
            self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
