#!/usr/bin/env bash
# Check that separate worktrees share build slots, but test execution does not.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 - "$SCRIPT_DIR/lib/swift_build_slots.py" <<'PY'
import pathlib
import subprocess
import sys
import tempfile
import time

helper = sys.argv[1]
child_code = r'''
import pathlib, sys, time
root = pathlib.Path(sys.argv[1])
name = sys.argv[2]
(root / ('started-' + name)).touch()
while not (root / ('release-' + name)).exists():
    time.sleep(0.02)
print('Build complete! (0.01s)', flush=True)
while not (root / ('finish-' + name)).exists():
    time.sleep(0.02)
'''

with tempfile.TemporaryDirectory(prefix="kswiftk-build-slots-") as tmp:
    root = pathlib.Path(tmp)
    processes = []

    def start(name):
        process = subprocess.Popen(
            [sys.executable, helper, '1', str(root / 'locks'),
             sys.executable, '-u', '-c', child_code, tmp, name],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        processes.append(process)
        return process

    def wait_for(path):
        deadline = time.monotonic() + 10
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        if not path.exists():
            raise AssertionError(f'timed out waiting for {path.name}')

    try:
        first = start('first')
        wait_for(root / 'started-first')
        second = start('second')
        time.sleep(0.5)
        assert not (root / 'started-second').exists(), 'second build did not wait'
        (root / 'release-first').touch()
        wait_for(root / 'started-second')
        assert first.poll() is None, 'the first test finished before the second build started'
        (root / 'release-second').touch()
        (root / 'finish-second').touch()
        assert second.wait(timeout=10) == 0
        (root / 'finish-first').touch()
        assert first.wait(timeout=10) == 0

        # If a wrapper is killed abruptly, its child keeps the lock until the
        # build actually exits; otherwise another build could overlap it.
        third = start('third')
        wait_for(root / 'started-third')
        third.kill()
        assert third.wait(timeout=10) != 0
        fourth = start('fourth')
        time.sleep(0.5)
        assert not (root / 'started-fourth').exists(), 'killed wrapper released a live build slot'
        (root / 'release-third').touch()
        (root / 'finish-third').touch()
        wait_for(root / 'started-fourth')
        (root / 'release-fourth').touch()
        (root / 'finish-fourth').touch()
        assert fourth.wait(timeout=10) == 0

        # Normal termination is forwarded to the child and releases the slot.
        fifth = start('fifth')
        wait_for(root / 'started-fifth')
        fifth.terminate()
        assert fifth.wait(timeout=10) != 0
        sixth = start('sixth')
        wait_for(root / 'started-sixth')
        (root / 'release-sixth').touch()
        (root / 'finish-sixth').touch()
        assert sixth.wait(timeout=10) == 0
    finally:
        (root / 'release-third').touch()
        (root / 'finish-third').touch()
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)

print('PASS: cross-worktree build slots and release before test execution')
PY
