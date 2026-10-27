#!/usr/bin/env python3
"""Limit concurrent local SwiftPM builds, releasing a slot before tests run."""

import fcntl
import os
import pathlib
import re
import signal
import subprocess
import sys
import threading
import time

sys.dont_write_bytecode = True
import test_stdlib_provenance


BUILD_COMPLETE = re.compile(rb"(?:^|[\r\n])Build complete!(?:[ \t(\r\n]|$)")


def acquire(directory: pathlib.Path, slots: int, cancel=None):
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    announced = False
    while True:
        if cancel is not None and cancel():
            return None
        for index in range(slots):
            handle = (directory / f"slot-{index}.lock").open("a+")
            try:
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return handle
            except BlockingIOError:
                handle.close()
        if not announced:
            print(f"swift build: waiting for one of {slots} local Swift build slots...", file=sys.stderr, flush=True)
            announced = True
        time.sleep(0.25)


def main() -> int:
    slots = int(sys.argv[1])
    directory = pathlib.Path(sys.argv[2])
    command = sys.argv[3:]
    handle = acquire(directory, slots)
    child = None
    released = False
    provenance = test_stdlib_provenance.prepare(command)
    provenance_thread = None

    def attest_when_requested():
        assert provenance is not None
        while not provenance.cancelled.wait(0.2):
            if not provenance.requested():
                continue
            provenance.acquire_worker_slot = lambda: acquire(
                directory, slots, lambda: provenance.cancelled.is_set() or not provenance.requested()
            )
            provenance.finish()
            return

    def forward(signum, _frame):
        if child is not None and child.poll() is None:
            try:
                child.send_signal(signum)
            except ProcessLookupError:
                pass

    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, forward)

    try:
        # Keeping the lock descriptor in the child prevents an abrupt wrapper
        # exit from letting another build start while swift is still running.
        environment = provenance.child_environment() if provenance else None
        child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 pass_fds=(handle.fileno(),), env=environment)
        tail = b""
        assert child.stdout is not None
        while True:
            chunk = os.read(child.stdout.fileno(), 65536)
            if not chunk:
                break
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
            if not released:
                text = tail + chunk
                if BUILD_COMPLETE.search(text):
                    fcntl.flock(handle, fcntl.LOCK_UN)
                    released = True
                    if provenance:
                        provenance_thread = threading.Thread(target=attest_when_requested, daemon=True)
                        provenance_thread.start()
                tail = text[-128:]
        child.stdout.close()
        code = child.wait()
        return 128 - code if code < 0 else code
    finally:
        if child is not None and child.poll() is None:
            child.terminate()
            child.wait()
        if provenance:
            provenance.close()
            if provenance_thread:
                provenance_thread.join(timeout=3)
                provenance.close()
        handle.close()


if __name__ == "__main__":
    sys.exit(main())
