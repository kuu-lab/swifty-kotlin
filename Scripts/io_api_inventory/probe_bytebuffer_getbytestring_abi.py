#!/usr/bin/env python3
"""Probe the pinned JVM classfile ABI and remaining-mask behavior for one bridge."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
LOCK = HERE / "upstream-lock.json"
PROBE = HERE / "probes/ByteBufferGetByteStringJvmAbiProbe.java"
EXPECTED_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"
EXPECTED_VERSION = "2.3.10"
ARTIFACT_COORDINATE = "org.jetbrains.kotlinx:kotlinx-io-bytestring-jvm:0.9.1"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jars-dir", required=True, type=Path,
                        help="Directory containing the locked kotlinx-io-bytestring-jvm 0.9.1 jar")
    parser.add_argument("--kotlin-home", required=True, type=Path,
                        help="Kotlin 2.3.10 distribution whose lib directory contains kotlin-stdlib")
    parser.add_argument("--java", default="java", help="Java launcher (default: java on PATH)")
    parser.add_argument("--download-missing", action="store_true",
                        help="download the pinned bytestring jar into --jars-dir when it is absent")
    args = parser.parse_args()

    try:
        lock = json.loads(LOCK.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return fail(f"cannot read pinned upstream lock: {error}")
    if lock.get("commit") != EXPECTED_COMMIT or lock.get("kotlinCompilerVersion") != EXPECTED_VERSION:
        return fail("the JVM ABI probe lock must remain on kotlinx-io 0.9.1 / Kotlin 2.3.10")

    artifact = next((entry for entry in lock.get("mavenArtifacts", [])
                     if entry.get("coordinate") == ARTIFACT_COORDINATE), None)
    if artifact is None:
        return fail(f"missing locked artifact: {ARTIFACT_COORDINATE}")
    filename = artifact["url"].rsplit("/", 1)[-1]
    jar = args.jars_dir / filename
    if not jar.is_file():
        alternatives = [args.jars_dir / "kotlinx-io-bytestring-jvm.jar"]
        jar = next((path for path in alternatives if path.is_file()), jar)
    if not jar.is_file() and args.download_missing:
        args.jars_dir.mkdir(parents=True, exist_ok=True)
        temporary_path = None
        try:
            with tempfile.NamedTemporaryFile(dir=args.jars_dir, prefix=".bytebuffer-abi-", delete=False) as stream:
                temporary_path = Path(stream.name)
                with urllib.request.urlopen(artifact["url"], timeout=30) as response:
                    shutil.copyfileobj(response, stream)
            if sha256(temporary_path) != artifact["sha256"]:
                return fail("downloaded JVM artifact SHA-256 does not match the upstream lock")
            temporary_path.replace(jar)
        except Exception as error:
            return fail(f"could not download pinned JVM artifact: {error}")
        finally:
            if temporary_path is not None and temporary_path.exists():
                temporary_path.unlink()
    if not jar.is_file():
        return fail(f"missing locked JVM artifact {filename} in {args.jars_dir}")
    jar_hash = sha256(jar)
    if jar_hash != artifact.get("sha256"):
        return fail(f"JVM artifact SHA-256 mismatch: {jar_hash}")

    kotlin_home = args.kotlin_home.resolve()
    stdlib_candidates = [kotlin_home / "lib/kotlin-stdlib.jar"]
    stdlib_candidates.extend(sorted((kotlin_home / "lib").glob("kotlin-stdlib-*.jar")))
    stdlib = next((path for path in stdlib_candidates if path.is_file()), None)
    if stdlib is None:
        return fail(f"cannot find kotlin-stdlib under {kotlin_home / 'lib'}")
    java = shutil.which(args.java)
    if java is None:
        return fail(f"Java launcher not found: {args.java}")

    command = [java, "-cp", os.pathsep.join((str(jar), str(stdlib))), str(PROBE)]
    result = subprocess.run(command, cwd=REPO, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        print("COMMAND " + " ".join(command))
        if result.stdout:
            print("STDOUT\n" + result.stdout, end="" if result.stdout.endswith("\n") else "\n")
        if result.stderr:
            print("STDERR\n" + result.stderr, end="" if result.stderr.endswith("\n") else "\n")
        return fail(f"JVM ABI probe failed with exit code {result.returncode}")

    print(f"reference_version={EXPECTED_VERSION}")
    print(f"reference_commit={EXPECTED_COMMIT}")
    print(f"artifact={ARTIFACT_COORDINATE} sha256={jar_hash}")
    print(f"probe_sha256={sha256(PROBE)}")
    print(f"kotlin_stdlib={stdlib} sha256={sha256(stdlib)}")
    print(f"java={java}")
    print("result=PASS")
    print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
