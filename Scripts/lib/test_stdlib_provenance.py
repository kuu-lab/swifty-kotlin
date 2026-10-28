"""Attest the compiler objects linked into a focused swiftbuild test product."""

from __future__ import annotations

import hashlib
import fcntl
import json
import os
import pathlib
import platform
import shlex
import stat
import subprocess
import sys
import tempfile
import threading
import time
import uuid


PRODUCTS = {"CompilerCoreTests", "CompilerBackendTests"}
OBJECTS = ("CompilerCore.o", "CompilerBackend.o", "RuntimeABI.o")


def file_hash(path: pathlib.Path) -> str:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    try:
        before = os.fstat(fd)
        digest = hashlib.sha256()
        while chunk := os.read(fd, 1024 * 1024):
            digest.update(chunk)
        after = os.fstat(fd)
        if (before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (
            after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns
        ):
            raise OSError("file changed while hashing")
        return digest.hexdigest()
    finally:
        os.close(fd)


def product_from_command(command: list[str]) -> str | None:
    if command[:2] != ["swift", "test"] or "--skip-build" in command:
        return None
    if any(os.environ.get(name) for name in ("DYLD_INSERT_LIBRARIES", "SWIFT_EXEC", "CC", "CXX", "LD")):
        return None
    product = None
    i = 2
    while i < len(command):
        arg = command[i]
        if arg == "--test-product" and i + 1 < len(command):
            product = command[i + 1]
            i += 2
        elif arg.startswith("--test-product="):
            product = arg.split("=", 1)[1]
            i += 1
        elif arg in ("--filter", "--num-workers", "-j", "--jobs") and i + 1 < len(command):
            i += 2
        elif arg == "--build-system" and i + 1 < len(command) and command[i + 1] == "swiftbuild":
            i += 2
        elif arg == "-Xswiftc" and command[i:i + 3] == ["-Xswiftc", "-plugin-path", "-Xswiftc"] and i + 3 < len(command):
            i += 4
        elif arg in ("--no-parallel", "--parallel", "--disable-sandbox", "--build-system=swiftbuild"):
            i += 1
        elif arg.startswith(("--filter=", "--num-workers=", "--jobs=")) or (arg.startswith("-j") and arg[2:].isdigit()):
            i += 1
        else:
            # Unknown build flags or layouts must keep the full-image key.
            return None
    return product if product in PRODUCTS else None


def input_paths(root: pathlib.Path, product: str, products: pathlib.Path) -> tuple[pathlib.Path, ...]:
    architecture = platform.machine()
    modules = tuple(products / f"{name}.swiftmodule/{architecture}-apple-macos.swiftmodule"
                    for name in ("CompilerCore", "CompilerBackend", "RuntimeABI"))
    prefix = root / ".build/out/Intermediates.noindex/KSwiftK.build/Debug"
    test_objects = prefix / f"{product}-p.build/Objects-normal"
    matches = list(test_objects.glob(f"*/{product}.LinkFileList"))
    if len(matches) != 1:
        raise ValueError("test linker input list is unavailable")
    inputs = [pathlib.Path(value).resolve(strict=True) for value in shlex.split(matches[0].read_text())]
    if len(inputs) != len(set(inputs)) or any(path.suffix != ".o" for path in inputs):
        raise ValueError("test linker inputs are ambiguous")
    test_root = test_objects.resolve()
    build_root = (root / ".build/out").resolve()
    shared = tuple(path for path in inputs if not path.is_relative_to(test_root))
    if any(not path.is_relative_to(build_root) for path in shared):
        raise ValueError("a linked dependency is outside the build directory")
    required = OBJECTS + ("TestStdlibCache.o",)
    if any(shared.count((products / name).resolve()) != 1 for name in required):
        raise ValueError("test linker inputs do not contain the expected compiler objects")
    return tuple(sorted(shared + modules))


def file_signature(path: pathlib.Path) -> tuple[int, int, int, int, int]:
    value = path.lstat()
    if not stat.S_ISREG(value.st_mode):
        raise ValueError("an input is not a regular file")
    return value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns, value.st_ctime_ns


def snapshot(root: pathlib.Path, product: str, products: pathlib.Path) -> dict[str, str]:
    return {str(path): file_hash(path) for path in input_paths(root, product, products)}


def snapshot_signatures(root: pathlib.Path, product: str, products: pathlib.Path) -> dict[str, tuple[int, int, int, int, int]]:
    return {str(path): file_signature(path) for path in input_paths(root, product, products)}


def toolchain_signatures() -> dict:
    tools = {}
    for name in ("swiftc", "clang", "ld"):
        path = subprocess.run(["xcrun", "--find", name], capture_output=True, text=True, timeout=30, check=True).stdout.strip()
        tools[name] = {"path": path, "signature": file_signature(pathlib.Path(path).resolve(strict=True))}
    sdk = subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True, text=True, timeout=30, check=True).stdout.strip()
    return {"tools": tools, "sdk": sdk, "sdkOverride": os.environ.get("SDKROOT", ""),
            "developer": os.environ.get("DEVELOPER_DIR", ""), "toolchains": os.environ.get("TOOLCHAINS", "")}


def toolchain_identity() -> dict:
    signatures = toolchain_signatures()
    tools = {name: {"path": value["path"], "hash": file_hash(pathlib.Path(value["path"]).resolve(strict=True))}
             for name, value in signatures["tools"].items()}
    swift_version = subprocess.run(["swift", "--version"], capture_output=True, text=True, timeout=30, check=True).stdout
    swiftc_version = subprocess.run([tools["swiftc"]["path"], "--version"], capture_output=True, text=True, timeout=30, check=True).stdout
    if swift_version != swiftc_version:
        raise ValueError("the test and worker Swift toolchains differ")
    if signatures != toolchain_signatures():
        raise ValueError("the toolchain changed while hashing")
    return {**signatures, "tools": tools, "version": swift_version}


def has_runtime_interposition(image: pathlib.Path) -> bool:
    completed = subprocess.run(["otool", "-l", str(image)], capture_output=True, text=True, timeout=30)
    if completed.returncode != 0:
        return True
    return any(name in completed.stdout for name in ("__swift5_replace", "__swift5_replac2", "__interpose"))


def atomic_json(path: pathlib.Path, value: dict) -> None:
    fd, temporary = tempfile.mkstemp(prefix=".write-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(value, output, sort_keys=True)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class Provenance:
    def __init__(self, root: pathlib.Path, product: str):
        self.root = root
        self.product = product
        self.products = root / ".build/out/Products/Debug"
        self.image = self.products / f"{product}.xctest/Contents/MacOS/{product}"
        self.directory = root / ".build/kswiftk-test-provenance"
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.before_objects = snapshot_signatures(self.root, self.product, self.products)
        self.before_image = file_signature(self.image)
        self.before_toolchain = toolchain_signatures()
        self.cancelled = threading.Event()
        self.acquire_worker_slot = None
        self.marker = self.directory / f"pending-{uuid.uuid4()}.json"
        atomic_json(self.marker, {"state": "pending"})

    def child_environment(self) -> dict[str, str]:
        environment = dict(os.environ)
        environment["KSWIFTK_TEST_STDLIB_PROVENANCE"] = str(self.marker)
        return environment

    def requested(self) -> bool:
        return any(self.directory.glob(self.marker.name + ".request-*"))

    def finish(self) -> None:
        if self.cancelled.is_set():
            return
        try:
            self._finish()
        except Exception as error:
            # Failure to prove identity is a cache miss, never a test failure.
            if os.environ.get("KSWIFTK_TEST_STDLIB_PROVENANCE_DEBUG") == "1":
                print(f"test stdlib provenance unavailable: {error}", file=sys.stderr, flush=True)
            if not self.cancelled.is_set():
                try:
                    atomic_json(self.marker, {"state": "unavailable"})
                except OSError:
                    pass

    def _finish(self) -> None:
        after_signatures = snapshot_signatures(self.root, self.product, self.products)
        image_signature = file_signature(self.image)
        if self.before_objects != after_signatures or self.before_toolchain != toolchain_signatures():
            raise ValueError("compiler objects changed while building")
        after_objects = snapshot(self.root, self.product, self.products)
        image_hash = file_hash(self.image)
        toolchain = toolchain_identity()
        if has_runtime_interposition(self.image):
            raise ValueError("test image contains runtime replacements")

        proof = self.directory / f"image-{image_hash}.json"
        if image_signature == self.before_image:
            # Only a previous attestation can establish what an unchanged
            # binary was linked from; the current objects alone cannot.
            existing = json.loads(proof.read_text())
            if existing.get("objects") != after_objects:
                raise ValueError("no matching prior attestation")

        worker, worker_hash = self._worker(after_objects, toolchain)
        if (self.cancelled.is_set() or snapshot_signatures(self.root, self.product, self.products) != after_signatures
                or file_signature(self.image) != image_signature or self.before_toolchain != toolchain_signatures()):
            raise ValueError("inputs changed during worker linking")
        inputs_hash = hashlib.sha256(json.dumps(after_objects, sort_keys=True).encode()).hexdigest()
        record = {"state": "ready", "imageHash": image_hash, "inputsHash": inputs_hash,
                  "workerPath": str(worker), "workerHash": worker_hash}
        atomic_json(proof, {"objects": after_objects})
        atomic_json(self.marker, record)

    def _worker(self, objects: dict[str, str], toolchain: dict) -> tuple[pathlib.Path, str]:
        source = self.root / "Scripts/test_stdlib_worker.swift"
        material = {"objects": objects, "source": file_hash(source), "toolchain": toolchain}
        key = hashlib.sha256(json.dumps(material, sort_keys=True).encode()).hexdigest()
        metadata = self.directory / f"worker-{key}.json"

        def cached_worker():
            try:
                previous = json.loads(metadata.read_text())
                path = pathlib.Path(previous["path"])
                if path.parent == self.products and path.name.startswith(f".kswiftk-test-stdlib-worker-{key}-"):
                    digest = file_hash(path)
                    if digest == previous["hash"] and os.access(path, os.X_OK):
                        return path, digest
            except (OSError, ValueError, KeyError, json.JSONDecodeError):
                pass
            return None

        if existing := cached_worker():
            return existing
        lock_path = self.directory / f"worker-{key}.lock"
        lock = os.open(lock_path, os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0), 0o600)
        try:
            while True:
                if self.cancelled.is_set() or not self.requested():
                    raise ValueError("worker request was cancelled")
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    time.sleep(0.1)
            if existing := cached_worker():
                return existing
            if self.acquire_worker_slot is None:
                raise ValueError("no worker build slot is available")
            slot = self.acquire_worker_slot()
            if slot is None:
                raise ValueError("worker request was cancelled while waiting for a slot")
            try:
                if self.cancelled.is_set() or not self.requested():
                    raise ValueError("worker request was cancelled before linking")
                path = self.products / f".kswiftk-test-stdlib-worker-{key}-{uuid.uuid4()}"
                environment = dict(os.environ)
                environment["CLANG_MODULE_CACHE_PATH"] = str(self.directory / "clang-module-cache")
                command = ["xcrun", "swiftc", "-parse-as-library", "-I", str(self.products), str(source)]
                command += [str(self.products / name) for name in OBJECTS]
                command += ["-o", str(path)]
                with tempfile.TemporaryFile() as errors:
                    process = subprocess.Popen(command, env=environment, stdout=subprocess.DEVNULL,
                                               stderr=errors, pass_fds=(slot.fileno(), lock))
                    deadline = time.monotonic() + 120
                    while process.poll() is None:
                        if self.cancelled.is_set() or not self.requested() or time.monotonic() >= deadline:
                            process.terminate()
                            try:
                                process.wait(timeout=2)
                            except subprocess.TimeoutExpired:
                                process.kill()
                                process.wait()
                            path.unlink(missing_ok=True)
                            raise ValueError("worker linking was cancelled")
                        time.sleep(0.1)
                    if process.returncode != 0:
                        errors.seek(0)
                        detail = errors.read().decode("utf-8", errors="replace")[-2000:]
                        path.unlink(missing_ok=True)
                        raise ValueError(f"could not link the isolated stdlib worker: {detail}")
                digest = file_hash(path)
                atomic_json(metadata, {"path": str(path), "hash": digest})
                return path, digest
            finally:
                # The linker inherits this description. Closing our copy
                # keeps the slot held until every descendant has exited.
                slot.close()
        finally:
            # As with the build slot, an orphaned linker retains this lock.
            os.close(lock)

    def close(self) -> None:
        self.cancelled.set()
        for path in [self.marker, *self.directory.glob(self.marker.name + ".request-*")]:
            try:
                path.unlink()
            except OSError:
                pass


def prepare(command: list[str]) -> Provenance | None:
    if platform.system() != "Darwin" or os.environ.get("KSWIFTK_TEST_STDLIB_PROVENANCE_DISABLE") == "1":
        return None
    product = product_from_command(command)
    if product is None:
        return None
    try:
        return Provenance(pathlib.Path.cwd().resolve(), product)
    except Exception:
        return None
