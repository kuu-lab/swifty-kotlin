#!/usr/bin/env python3
"""Exercise compiler-only attestation without running a Swift build."""

import json
import hashlib
import fcntl
import os
import pathlib
import platform
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "lib"))
import test_stdlib_provenance as provenance
import swift_build_slots


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        toolchain = patch.object(provenance, "toolchain_identity", return_value={"fixture": "toolchain"})
        toolchain.start()
        self.addCleanup(toolchain.stop)
        signatures = patch.object(provenance, "toolchain_signatures", return_value={"fixture": "toolchain"})
        signatures.start()
        self.addCleanup(signatures.stop)
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.products = self.root / ".build/out/Products/Debug"
        self.products.mkdir(parents=True)
        shared_objects = provenance.OBJECTS + ("TestStdlibCache.o", "CompilerTestSupport.o")
        for name in shared_objects:
            (self.products / name).write_bytes((name + "-old").encode())
        for name in ("CompilerCore", "CompilerBackend", "RuntimeABI"):
            module = self.products / f"{name}.swiftmodule/{platform.machine()}-apple-macos.swiftmodule"
            module.parent.mkdir()
            module.write_bytes((name + "-module").encode())
        self.image = self.products / "CompilerBackendTests.xctest/Contents/MacOS/CompilerBackendTests"
        self.image.parent.mkdir(parents=True)
        self.image.write_bytes(b"test-before")
        link = self.root / ".build/out/Intermediates.noindex/KSwiftK.build/Debug/CompilerBackendTests-p.build/Objects-normal/arm64/CompilerBackendTests.LinkFileList"
        link.parent.mkdir(parents=True)
        self.test_object = link.parent / "TestCase.o"
        self.test_object.write_bytes(b"test-code-before")
        link.write_text(" ".join([str(self.test_object)] + [str(self.products / name) for name in shared_objects]))
        self.worker = self.products / ".kswiftk-test-stdlib-worker-fixture"
        self.worker.write_bytes(b"worker")

    def finish(self, attestation):
        with patch.object(provenance, "has_runtime_interposition", return_value=False), \
             patch.object(attestation, "_worker", return_value=(self.worker, provenance.file_hash(self.worker))):
            attestation.finish()
        return json.loads(attestation.marker.read_text())

    def test_test_only_relink_attests_same_compiler_objects(self):
        attestation = provenance.Provenance(self.root, "CompilerBackendTests")
        self.test_object.write_bytes(b"test-code-after")
        self.image.write_bytes(b"test-after!")
        record = self.finish(attestation)
        self.assertEqual(record["state"], "ready")
        self.assertEqual(record["imageHash"], provenance.file_hash(self.image))
        self.assertEqual(record["workerHash"], provenance.file_hash(self.worker))
        inputs = provenance.snapshot(self.root, "CompilerBackendTests", self.products)
        self.assertEqual(record["inputsHash"], hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest())
        attestation.close()

    def test_same_size_and_mtime_compiler_change_cannot_be_attested(self):
        attestation = provenance.Provenance(self.root, "CompilerBackendTests")
        compiler = self.products / "CompilerBackend.o"
        original = compiler.stat()
        contents = compiler.read_bytes()
        compiler.write_bytes(bytes([contents[0] ^ 1]) + contents[1:])
        os.utime(compiler, ns=(original.st_atime_ns, original.st_mtime_ns))
        self.image.write_bytes(b"test-after!")
        self.assertEqual(self.finish(attestation)["state"], "unavailable")

    def test_changed_test_support_object_cannot_be_attested(self):
        attestation = provenance.Provenance(self.root, "CompilerBackendTests")
        (self.products / "TestStdlibCache.o").write_bytes(b"changed cache logic")
        self.image.write_bytes(b"test-after!")
        self.assertEqual(self.finish(attestation)["state"], "unavailable")

    def test_unchanged_image_without_prior_proof_is_not_attested(self):
        attestation = provenance.Provenance(self.root, "CompilerBackendTests")
        self.assertEqual(self.finish(attestation)["state"], "unavailable")

    def test_an_existing_proof_can_be_reused_for_the_same_image(self):
        first = provenance.Provenance(self.root, "CompilerBackendTests")
        self.image.write_bytes(b"test-after!")
        self.assertEqual(self.finish(first)["state"], "ready")
        first.close()
        second = provenance.Provenance(self.root, "CompilerBackendTests")
        self.assertEqual(self.finish(second)["state"], "ready")

    def test_request_is_detected_only_while_a_caller_is_waiting(self):
        attestation = provenance.Provenance(self.root, "CompilerBackendTests")
        self.assertFalse(attestation.requested())
        request = attestation.marker.with_name(attestation.marker.name + ".request-one")
        request.touch()
        self.assertTrue(attestation.requested())
        request.unlink()
        self.assertFalse(attestation.requested())
        request.touch()
        attestation.close()
        self.assertFalse(request.exists())
        self.assertFalse(attestation.marker.exists())

    def test_build_without_a_stdlib_request_never_links_a_worker(self):
        class FakeProvenance:
            cancelled = threading.Event()
            finished = False

            def child_environment(self):
                return dict(os.environ)

            def requested(self):
                return False

            def finish(self):
                self.finished = True

            def close(self):
                self.cancelled.set()

        fake = FakeProvenance()
        command = ["slots", "1", str(self.root / "slots"), sys.executable, "-c", "print('Build complete!')"]
        with patch.object(provenance, "prepare", return_value=fake), \
             patch.object(swift_build_slots.signal, "signal"), patch.object(sys, "argv", command):
            self.assertEqual(swift_build_slots.main(), 0)
        self.assertFalse(fake.finished)

    def test_runtime_interposition_is_rejected(self):
        attestation = provenance.Provenance(self.root, "CompilerBackendTests")
        self.image.write_bytes(b"test-after!")
        with patch.object(provenance, "has_runtime_interposition", return_value=True):
            attestation.finish()
        self.assertEqual(json.loads(attestation.marker.read_text())["state"], "unavailable")

    def test_objects_changing_during_worker_link_are_rejected(self):
        attestation = provenance.Provenance(self.root, "CompilerBackendTests")
        self.image.write_bytes(b"test-after!")

        def changing_worker(_objects, _toolchain):
            (self.products / "CompilerCore.o").write_bytes(b"changed")
            return self.worker, provenance.file_hash(self.worker)

        with patch.object(provenance, "has_runtime_interposition", return_value=False), \
             patch.object(attestation, "_worker", side_effect=changing_worker):
            attestation.finish()
        self.assertEqual(json.loads(attestation.marker.read_text())["state"], "unavailable")

    def test_changed_toolchain_prevents_attestation(self):
        attestation = provenance.Provenance(self.root, "CompilerBackendTests")
        self.image.write_bytes(b"test-after!")
        with patch.object(provenance, "toolchain_signatures", return_value={"fixture": "different"}):
            self.assertEqual(self.finish(attestation)["state"], "unavailable")

    def test_existing_worker_needs_no_build_slot_and_rejects_corruption(self):
        attestation = provenance.Provenance(self.root, "CompilerBackendTests")
        source = self.root / "Scripts/test_stdlib_worker.swift"
        source.parent.mkdir()
        source.write_text("worker source")
        objects = provenance.snapshot(self.root, "CompilerBackendTests", self.products)
        toolchain = {"fixture": "toolchain"}
        material = {"objects": objects, "source": provenance.file_hash(source), "toolchain": toolchain}
        key = hashlib.sha256(json.dumps(material, sort_keys=True).encode()).hexdigest()
        worker = self.products / f".kswiftk-test-stdlib-worker-{key}-fixture"
        worker.write_bytes(b"worker-a")
        worker.chmod(0o700)
        metadata = attestation.directory / f"worker-{key}.json"
        metadata.write_text(json.dumps({"path": str(worker), "hash": provenance.file_hash(worker)}))
        attestation.acquire_worker_slot = lambda: self.fail("a cached worker must not wait for a build slot")
        self.assertEqual(attestation._worker(objects, toolchain)[0], worker)

        worker.write_bytes(b"worker-b")
        request = attestation.marker.with_name(attestation.marker.name + ".request-test")
        request.touch()
        attestation.acquire_worker_slot = lambda: None
        with self.assertRaises(ValueError):
            attestation._worker(objects, toolchain)

    def test_linker_keeps_build_slot_if_its_wrapper_is_killed(self):
        source = self.root / "Scripts/test_stdlib_worker.swift"
        source.parent.mkdir()
        source.write_text("worker source")
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        started = self.root / "link-started"
        release = self.root / "link-release"
        linker = bin_dir / "xcrun"
        linker.write_text(
            "#!" + sys.executable + "\n"
            "import os,pathlib,sys,time\n"
            f"started=pathlib.Path({str(started)!r}); release=pathlib.Path({str(release)!r})\n"
            "started.write_text(str(os.getpid()))\n"
            "while not release.exists(): time.sleep(0.05)\n"
            "output=pathlib.Path(sys.argv[-1]); output.write_bytes(b'worker'); output.chmod(0o700)\n"
        )
        linker.chmod(0o700)
        lock_path = self.root / "link-slot.lock"
        code = r'''
import fcntl, pathlib, sys, threading
sys.path.insert(0, sys.argv[1])
import test_stdlib_provenance as p
root = pathlib.Path(sys.argv[2])
item = p.Provenance.__new__(p.Provenance)
item.root = root
item.products = root / '.build/out/Products/Debug'
item.directory = root / '.build/kswiftk-test-provenance'
item.directory.mkdir(parents=True, exist_ok=True)
item.marker = item.directory / 'pending-fixture.json'
(item.directory / (item.marker.name + '.request-fixture')).touch()
item.cancelled = threading.Event()
def slot():
    handle = open(sys.argv[3], 'a+')
    fcntl.flock(handle, fcntl.LOCK_EX)
    return handle
item.acquire_worker_slot = slot
item._worker({'object': 'digest'}, {'toolchain': 'fixture'})
'''
        environment = dict(os.environ)
        environment["PATH"] = str(bin_dir) + os.pathsep + environment.get("PATH", "")
        parent = subprocess.Popen([sys.executable, "-c", code, str(pathlib.Path(provenance.__file__).parent),
                                   str(self.root), str(lock_path)], env=environment,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        child_pid = None
        try:
            deadline = time.monotonic() + 10
            while not started.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertTrue(started.exists(), "fake linker did not start")
            child_pid = int(started.read_text())
            parent.kill()
            parent.wait(timeout=5)
            worker_locks = list((self.root / ".build/kswiftk-test-provenance").glob("worker-*.lock"))
            self.assertEqual(len(worker_locks), 1)
            with lock_path.open("a+") as contender:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with worker_locks[0].open("a+") as worker_contender:
                    with self.assertRaises(BlockingIOError):
                        fcntl.flock(worker_contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
                release.touch()
                deadline = time.monotonic() + 10
                while True:
                    try:
                        fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        break
                    except BlockingIOError:
                        self.assertLess(time.monotonic(), deadline, "linker never released the slot")
                        time.sleep(0.05)
                fcntl.flock(contender, fcntl.LOCK_UN)
            child_pid = None
        finally:
            release.touch(exist_ok=True)
            if parent.poll() is None:
                parent.kill()
                parent.wait()
            if child_pid is not None:
                try:
                    command = subprocess.run(["ps", "-p", str(child_pid), "-o", "command="], capture_output=True, text=True)
                    if command.returncode == 0 and str(linker) in command.stdout:
                        os.kill(child_pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass

    def test_unknown_build_flags_do_not_enable_the_optimization(self):
        base = ["swift", "test", "--test-product", "CompilerBackendTests"]
        self.assertEqual(provenance.product_from_command(base + ["--filter", "Example"]), "CompilerBackendTests")
        for extra in (["--skip-build"], ["-Xlinker", "-interposable"], ["--scratch-path", "/tmp/other"]):
            self.assertIsNone(provenance.product_from_command(base + list(extra)))

    @unittest.skipUnless(os.environ.get("KSWIFTK_TEST_STDLIB_WORKER_TEST_PATH"), "requires a linked worker")
    def test_worker_exits_when_its_parent_is_killed(self):
        worker = os.environ["KSWIFTK_TEST_STDLIB_WORKER_TEST_PATH"]
        supervisor_code = (
            "import subprocess,sys; "
            "p=subprocess.Popen([sys.argv[1],'--parent-watch-test'],stdout=subprocess.PIPE,text=True); "
            "assert p.stdout.readline().strip()=='ready'; print(p.pid,flush=True); p.wait()"
        )
        supervisor = subprocess.Popen([sys.executable, "-c", supervisor_code, worker],
                                      stdout=subprocess.PIPE, text=True)
        worker_pid = None
        worker_running = False
        try:
            worker_pid = int(supervisor.stdout.readline().strip())
            worker_running = True
            supervisor.terminate()
            supervisor.wait(timeout=5)
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                result = subprocess.run(["ps", "-p", str(worker_pid), "-o", "state="], capture_output=True, text=True)
                if result.returncode != 0 or result.stdout.strip().startswith("Z"):
                    worker_running = False
                    break
                time.sleep(0.1)
            else:
                self.fail("worker survived its parent")
        finally:
            if supervisor.poll() is None:
                supervisor.kill()
                supervisor.wait()
            if worker_pid is not None and worker_running:
                try:
                    result = subprocess.run(["ps", "-p", str(worker_pid), "-o", "command="], capture_output=True, text=True)
                    if result.returncode == 0 and result.stdout.strip() == worker + " --parent-watch-test":
                        os.kill(worker_pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            if supervisor.stdout is not None:
                supervisor.stdout.close()


if __name__ == "__main__":
    unittest.main()
