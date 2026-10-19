#!/usr/bin/env python3
"""Verify Buffer.seek stays inaccessible to an external KLIB consumer."""

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
DEFAULT_PROBE = HERE / "probes/buffer_seek_external_visibility.kt"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True, type=Path)
    parser.add_argument("--stdlib-library", required=True, type=Path)
    parser.add_argument("--probe", default=DEFAULT_PROBE, type=Path)
    args = parser.parse_args()

    compiler = args.compiler.resolve()
    stdlib = args.stdlib_library.resolve()
    probe = args.probe.resolve()
    manifest = stdlib / "manifest.json"
    command = [
        str(compiler), "-O0", "--no-incremental", "--stdlib-library", str(stdlib),
        "--emit", "library", "-m", "BufferSeekExternalVisibility", str(probe),
    ]
    with tempfile.TemporaryDirectory(prefix="buffer-seek-visibility-") as temporary:
        output = Path(temporary) / "probe.kklib"
        command += ["-o", str(output)]
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
        )

    codes = re.findall(r"error (KSWIFTK-[A-Z]+-\d+):", result.stderr)
    if result.returncode == 0:
        raise SystemExit("external KLIB consumer unexpectedly accessed internal Buffer.seek")
    if result.stdout or codes != ["KSWIFTK-SEMA-0044", "KSWIFTK-SEMA-0044"]:
        raise SystemExit("Buffer.seek visibility probe failed for an unexpected reason:\n" + result.stderr)
    if "it is internal in the bundled stdlib module" not in result.stderr:
        raise SystemExit("Buffer.seek visibility probe did not report the internal module boundary:\n" + result.stderr)

    print(json.dumps({
        "status": "PASS",
        "expected_result": "external consumer rejected",
        "candidate_compiler_sha256": sha(compiler),
        "stdlib_manifest_sha256": sha(manifest),
        "probe_sha256": sha(probe),
        "exit_code": result.returncode,
        "diagnostic_codes": codes,
        "stderr_sha256": hashlib.sha256(result.stderr.encode()).hexdigest(),
        "stderr": result.stderr,
        "command": command,
    }, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
