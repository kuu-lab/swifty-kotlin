#!/usr/bin/env python3
"""Verify the pinned JVM PublishedApi descriptor for ByteString's backing array."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / "Scripts/io_api_inventory/upstream-lock.json"
EXPECTED_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"
METHOD = "public final byte[] getBackingArrayReference();"


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jar", type=Path, required=True, help="pinned kotlinx-io-bytestring-jvm 0.9.1 jar")
    parser.add_argument("--javap", default="javap")
    args = parser.parse_args()

    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    if lock.get("commit") != EXPECTED_COMMIT:
        fail("upstream lock does not match kotlinx-io 0.9.1")
    artifact = next((entry for entry in lock["mavenArtifacts"]
                     if entry.get("coordinate") == "org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:0.9.1"), None)
    if artifact is None:
        fail("pinned ByteString JVM artifact is absent from upstream-lock.json")
    actual_hash = sha256(args.jar)
    if actual_hash != artifact["sha256"]:
        fail(f"pinned ByteString JVM artifact hash mismatch: {actual_hash}")

    command = [args.javap, "-classpath", str(args.jar), "-p", "-s", "-v", "kotlinx.io.bytestring.ByteString"]
    process = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if process.returncode != 0:
        fail(f"javap failed ({process.returncode}): {process.stderr.strip()}")
    lines = process.stdout.splitlines()
    starts = [index for index, line in enumerate(lines) if line.strip() == METHOD]
    if len(starts) != 1:
        fail(f"expected one {METHOD!r} declaration, found {len(starts)}")
    start = starts[0]
    end = next((index for index in range(start + 1, len(lines)) if not lines[index].strip()), len(lines))
    method = "\n".join(lines[start:end])
    if not re.search(r"^\s*descriptor:\s*\(\)\[B\s*$", method, re.MULTILINE):
        fail("getBackingArrayReference JVM descriptor is not ()[B")
    flags = re.search(r"^\s*flags:\s*\([^)]*\)(.*)$", method, re.MULTILINE)
    if not flags or not {"ACC_PUBLIC", "ACC_FINAL"}.issubset(set(re.findall(r"ACC_[A-Z_]+", flags.group(1)))):
        fail("getBackingArrayReference is not public final in the JVM ABI")
    if "ACC_STATIC" in flags.group(1):
        fail("getBackingArrayReference unexpectedly has ACC_STATIC")
    if "kotlin.PublishedApi" not in method:
        fail("getBackingArrayReference JVM method is missing kotlin.PublishedApi")

    print(json.dumps({
        "status": "PASS",
        "coordinate": artifact["coordinate"],
        "reference_commit": EXPECTED_COMMIT,
        "jar_sha256": actual_hash,
        "command": command,
        "javap_stdout_sha256": hashlib.sha256(process.stdout.encode()).hexdigest(),
        "method": METHOD,
        "descriptor": "()[B",
        "flags": sorted(set(re.findall(r"ACC_[A-Z_]+", flags.group(1)))),
        "published_api": True,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
