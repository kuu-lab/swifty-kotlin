#!/usr/bin/env python3
"""Inspect the pinned kotlinx-io JVM InternalIoApi class file."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


HERE = Path(__file__).resolve().parent
REFERENCE_LOCK = HERE.parents[1] / "Scripts/kotlinx_io_upstream/reference-lock.json"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jar", type=Path, required=True)
    parser.add_argument("--java", type=Path, required=True, help="Java executable from the pinned reference JDK")
    parser.add_argument("--output", type=Path, help="write the inspection receipt to this path")
    args = parser.parse_args()

    reference_lock = json.loads(REFERENCE_LOCK.read_text(encoding="utf-8"))
    jar_hash = hashlib.sha256(args.jar.read_bytes()).hexdigest()
    pinned = next(
        entry for entry in reference_lock["jvm_artifacts"]
        if entry["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1"
    )
    if jar_hash != pinned["sha256"]:
        raise SystemExit("the supplied kotlinx-io JVM jar does not match the pinned 0.9.1 artifact")

    java_version = subprocess.run(
        [str(args.java.resolve()), "-version"], capture_output=True, text=True, check=True
    )
    version_output = java_version.stdout + java_version.stderr
    version_match = re.search(r'version "(21\.[^"]+)"', version_output)
    if version_match is None:
        raise SystemExit("the JVM reference inspection requires Java 21")

    javap = args.java.resolve().with_name("javap")
    inspected = subprocess.run(
        [str(javap), "-v", "-classpath", str(args.jar.resolve()), "kotlinx.io.InternalIoApi"],
        check=True,
        capture_output=True,
        text=True,
    )
    output = inspected.stdout
    required = (
        "public interface kotlinx.io.InternalIoApi extends java.lang.annotation.Annotation",
        "ACC_PUBLIC, ACC_INTERFACE, ACC_ABSTRACT, ACC_ANNOTATION",
        "methods: 0",
        "kotlin.annotation.MustBeDocumented",
        "value=Lkotlin/annotation/AnnotationRetention;.BINARY",
        "java.lang.annotation.Documented",
        "value=Ljava/lang/annotation/RetentionPolicy;.CLASS",
        "level=Lkotlin/RequiresOptIn$Level;.ERROR",
        "This is an internal API and its use requires care.",
    )
    missing = [item for item in required if item not in output]
    if missing:
        raise SystemExit("pinned InternalIoApi class is missing expected JVM markers: " + ", ".join(missing))

    receipt = {
        "schema_version": 1,
        "class_name": "kotlinx.io.InternalIoApi",
        "java_version": version_match.group(1),
        "java_binary_sha256": hashlib.sha256(args.java.resolve().read_bytes()).hexdigest(),
        "reference_artifact_sha256": jar_hash,
        "class_output_sha256": hashlib.sha256(inspected.stdout.encode("utf-8")).hexdigest(),
        "class_output_bytes": len(inspected.stdout.encode("utf-8")),
        "class_flags": ["PUBLIC", "INTERFACE", "ABSTRACT", "ANNOTATION"],
        "method_count": 0,
        "kotlin_retention": "BINARY",
        "java_retention": "CLASS",
        "must_be_documented": True,
        "requires_opt_in_level": "ERROR",
        "candidate_descriptor_verified": False,
    }
    rendered = json.dumps(receipt, indent=2, ensure_ascii=False) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
