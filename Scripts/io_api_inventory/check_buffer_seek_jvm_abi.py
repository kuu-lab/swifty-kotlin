#!/usr/bin/env python3
"""Check the pinned kotlinx-io JVM ABI for Buffer.seek."""

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
LOCK = HERE.parent / "kotlinx_io_upstream" / "reference-lock.json"
DESCRIPTOR = "(Lkotlinx/io/Buffer;JLkotlin/jvm/functions/Function2;)Ljava/lang/Object;"
GENERIC_SIGNATURE = (
    "<T:Ljava/lang/Object;>(Lkotlinx/io/Buffer;JLkotlin/jvm/functions/Function2<"
    "-Lkotlinx/io/Segment;-Ljava/lang/Long;+TT;>;)TT;"
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jar", required=True, type=Path)
    parser.add_argument("--javap", default="javap")
    args = parser.parse_args()

    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    artifact = next(
        row for row in lock["jvm_artifacts"]
        if row["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1"
    )
    digest = hashlib.sha256(args.jar.read_bytes()).hexdigest()
    if digest != artifact["sha256"]:
        raise SystemExit(f"pinned JVM artifact hash mismatch: {digest}")

    result = subprocess.run(
        [args.javap, "-classpath", str(args.jar.resolve()), "-p", "-s", "-v", "kotlinx.io.BufferKt"],
        check=True,
        capture_output=True,
        text=True,
    )
    output = result.stdout
    headers = [
        index for index, line in enumerate(output.splitlines())
        if re.search(r"\bseek\(", line) and re.search(r"^\s*public static final <T", line)
    ]
    if len(headers) != 1:
        raise SystemExit(f"expected one generic public seek method, found {len(headers)}")

    lines = output.splitlines()
    start = headers[0]
    end = next((index for index in range(start + 1, len(lines)) if lines[index].startswith("SourceFile:")), len(lines))
    method = "\n".join(lines[start:end])
    descriptor_match = re.search(r"^\s*descriptor: (.+)$", method, re.MULTILINE)
    signature_match = re.search(r"^\s*Signature:.*// (.+)$", method, re.MULTILINE)
    flags_match = re.search(r"^\s*flags: .*\(([^)]*)\)(.*)$", method, re.MULTILINE)

    failures = []
    if not descriptor_match or descriptor_match.group(1) != DESCRIPTOR:
        failures.append("descriptor")
    if not signature_match or signature_match.group(1) != GENERIC_SIGNATURE:
        failures.append("generic signature")
    if not flags_match:
        failures.append("method flags")
    else:
        for flag in ("ACC_PUBLIC", "ACC_STATIC", "ACC_FINAL", "ACC_SYNTHETIC"):
            if flag not in flags_match.group(2):
                failures.append(flag)
    invisible = method.split("RuntimeInvisibleAnnotations:", 1)
    if len(invisible) != 2 or "kotlin.PublishedApi" not in invisible[1]:
        failures.append("PublishedApi")
    if "seek$default" in output:
        failures.append("unexpected seek default wrapper")
    if failures:
        raise SystemExit("Buffer.seek JVM ABI mismatch: " + ", ".join(failures))

    print(json.dumps({
        "status": "PASS",
        "subject": "pinned upstream JVM artifact",
        "coordinate": artifact["coordinate"],
        "jar_sha256": digest,
        "method": "kotlinx.io.BufferKt.seek",
        "descriptor": DESCRIPTOR,
        "generic_signature": GENERIC_SIGNATURE,
        "flags": ["ACC_PUBLIC", "ACC_STATIC", "ACC_FINAL", "ACC_SYNTHETIC"],
        "published_api_annotation": True,
        "default_wrapper": False,
    }, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, KeyError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
