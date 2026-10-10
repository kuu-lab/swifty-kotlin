#!/usr/bin/env python3
"""Deterministic command fixture used by test_run_matrix.py."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


mode = os.environ.get("KIO_FIXTURE", "same")
if mode == "hang":
    time.sleep(5)
elif mode == "hang-child":
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(15)"])
    Path(os.environ["KIO_ARTIFACT_DIR"], "child.pid").write_text(str(child.pid))
    def reap_child(signum, frame):
        child.wait(timeout=2)
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, reap_child)
    time.sleep(15)
elif mode == "crash":
    print("synthetic failure", file=sys.stderr)
    raise SystemExit(23)
elif mode == "invalid":
    print("not a JSON observation")
    raise SystemExit(0)

observation = {
    "stdout": "same output" if mode != "different" else "different output",
    "exception_type": None,
    "bytes_consumed": 4,
    "buffer_state": {"size": 0, "start": 0, "end": 0},
    "byte_buffer_state": None,
    "callbacks": {"close": 1, "flush": 1},
    "resource_lifecycle": {"closed": True},
}
if mode == "state-different":
    observation["byte_buffer_state"] = {"position": 1, "limit": 4}
print(json.dumps(observation, separators=(",", ":")))
