#!/usr/bin/env python3
"""Verify the pinned kotlinx-io Source/RawSource JVM and KLIB declaration shape."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile
import urllib.request
import zipfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
INVENTORY = REPO / "Scripts/io_api_inventory"
UPSTREAM = INVENTORY / "upstream/kotlinx-io-0.9.1"
LOCK = INVENTORY / "upstream-lock.json"
REFERENCE_LOCK = REPO / "Scripts/kotlinx_io_upstream/reference-lock.json"
PROBE = HERE / "SourceRawSourceJvmShapeProbe.java"
EXPECTED_COMMIT = "362bdc35e159bad6da1e08101c8321792d762281"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()


def read_locked_source(lock: dict, relative: str) -> bytes:
    path = UPSTREAM / relative
    data = path.read_bytes()
    entry = next((item for item in lock["upstreamFiles"] if item["path"] == relative), None)
    if entry is None or len(data) != entry["size"] or git_blob_sha(data) != entry["gitBlobSha"]:
        raise ValueError(f"upstream input is not pinned: {relative}")
    return data


def require_line(path: Path, expected: str) -> str:
    lines = path.read_text(encoding="utf-8").splitlines()
    matches = [line.strip() for line in lines if line.strip() == expected]
    if len(matches) != 1:
        raise ValueError(f"expected exactly one declaration line in {path}: {expected}")
    return matches[0]


def major_version(java: str) -> tuple[int, str]:
    result = subprocess.run([java, "-version"], text=True, capture_output=True, check=True)
    output = (result.stderr + result.stdout).strip()
    match = re.search(r'(?<![0-9])(?:version ")?(\d+)(?:\.|"|\s)', output)
    if match is None:
        raise ValueError(f"could not parse Java version: {output}")
    return int(match.group(1)), output


def download_artifact(artifact: dict, destination: Path) -> None:
    digest = hashlib.sha256()
    with urllib.request.urlopen(artifact["url"], timeout=60) as response, destination.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)
            digest.update(chunk)
    if digest.hexdigest() != artifact["sha256"]:
        destination.unlink(missing_ok=True)
        raise ValueError(f"JVM artifact SHA-256 mismatch: {artifact['coordinate']}")


def download_compiler_archive(artifact: dict, destination: Path) -> None:
    download_artifact(artifact, destination)


def pinned_kotlin_stdlib(reference_lock: dict, root: Path, kotlin_home: Path | None) -> Path:
    expected = next(entry for entry in reference_lock["sdk_files"] if entry["path"] == "lib/kotlin-stdlib.jar")
    if kotlin_home is not None:
        stdlib = kotlin_home / "lib/kotlin-stdlib.jar"
    else:
        archive_spec = reference_lock["compiler_archive"]
        archive_path = root / "kotlin-compiler-2.3.10.zip"
        download_compiler_archive(archive_spec, archive_path)
        with zipfile.ZipFile(archive_path) as archive:
            names = [name for name in archive.namelist() if name.endswith("/lib/kotlin-stdlib.jar")]
            if len(names) != 1:
                raise ValueError("pinned Kotlin compiler archive has no unique kotlin-stdlib.jar")
            data = archive.read(names[0])
        stdlib = root / "kotlin-stdlib-2.3.10.jar"
        stdlib.write_bytes(data)
    if sha256(stdlib.read_bytes()) != expected["sha256"]:
        raise ValueError("Kotlin stdlib does not match the pinned Kotlin 2.3.10 SHA-256")
    return stdlib


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--java", default="java")
    parser.add_argument("--javac", default="javac")
    parser.add_argument("--jar", type=Path, help="Use an already-downloaded locked JVM artifact")
    parser.add_argument("--kotlin-home", type=Path, help="Use a prepared Kotlin 2.3.10 installation")
    parser.add_argument("--output", type=Path, help="Write the exact PASS receipt JSON to this path")
    args = parser.parse_args()

    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    reference_lock = json.loads(REFERENCE_LOCK.read_text(encoding="utf-8"))
    if lock.get("tag") != "0.9.1" or lock.get("commit") != EXPECTED_COMMIT:
        raise ValueError("kotlinx-io upstream lock is not the required 0.9.1 commit")

    source_raw = read_locked_source(lock, "core/common/src/RawSource.kt").decode("utf-8")
    source_source = read_locked_source(lock, "core/common/src/Source.kt").decode("utf-8")
    klib_api = (UPSTREAM / "core/api/kotlinx-io-core.klib.api").read_bytes()
    jvm_api = (UPSTREAM / "core/api/kotlinx-io-core.api").read_bytes()
    if b"abstract interface kotlinx.io/RawSource : kotlin/AutoCloseable {" not in klib_api:
        raise ValueError("pinned KLIB API does not preserve RawSource -> kotlin/AutoCloseable")
    if b"sealed interface kotlinx.io/Source : kotlinx.io/RawSource {" not in klib_api:
        raise ValueError("pinned KLIB API does not preserve sealed Source -> RawSource")
    if b"public abstract interface class kotlinx/io/RawSource : java/lang/AutoCloseable {" not in jvm_api:
        raise ValueError("pinned JVM API does not preserve RawSource -> java/lang/AutoCloseable")
    if b"public abstract interface class kotlinx/io/Source : kotlinx/io/RawSource {" not in jvm_api:
        raise ValueError("pinned JVM API does not preserve Source -> RawSource")
    if not any(line.strip() == "public interface RawSource : AutoCloseable {" for line in source_raw.splitlines()):
        raise ValueError("pinned Kotlin source does not declare RawSource : AutoCloseable")
    if not any(line.strip() == "public sealed interface Source : RawSource {" for line in source_source.splitlines()):
        raise ValueError("pinned Kotlin source does not declare sealed Source : RawSource")

    artifact = next(
        entry for entry in lock["mavenArtifacts"]
        if entry["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1"
    )
    java_major, java_output = major_version(args.java)
    if java_major < 17:
        raise ValueError(f"Java 17 or newer is required for reflection; got {java_output}")

    with tempfile.TemporaryDirectory(prefix="kuu2615-jvm-shape-") as temporary:
        root = Path(temporary)
        stdlib = pinned_kotlin_stdlib(reference_lock, root, args.kotlin_home)
        stdlib_hash = sha256(stdlib.read_bytes())
        jar = args.jar
        if jar is None:
            jar = root / "kotlinx-io-core-jvm-0.9.1.jar"
            download_artifact(artifact, jar)
        jar = jar.resolve()
        jar_bytes = jar.read_bytes()
        if sha256(jar_bytes) != artifact["sha256"]:
            raise ValueError("provided JVM artifact does not match the pinned SHA-256")

        classes = root / "classes"
        classes.mkdir()
        classpath = os.pathsep.join((str(classes), str(jar), str(stdlib)))
        subprocess.run([args.javac, "-classpath", classpath, "-d", str(classes), str(PROBE)], check=True)
        result = subprocess.run(
            [args.java, "-classpath", classpath, "SourceRawSourceJvmShapeProbe"],
            text=True, capture_output=True,
        )
        if result.returncode != 0:
            raise ValueError(
                f"JVM shape probe failed with exit {result.returncode}; "
                f"stdout={result.stdout!r}; stderr={result.stderr!r}"
            )
        if result.stderr:
            raise ValueError(f"JVM shape probe wrote unexpected stderr: {result.stderr}")
        if '"result":"PASS"' not in result.stdout:
            raise ValueError(f"JVM shape probe returned an invalid receipt: {result.stdout}")

    receipt = {
        "result": "PASS",
        "reference_version": "kotlinx-io 0.9.1",
        "reference_commit": EXPECTED_COMMIT,
        "artifact_coordinate": artifact["coordinate"],
        "artifact_sha256": artifact["sha256"],
        "kotlin_version": "2.3.10",
        "kotlin_stdlib_sha256": stdlib_hash,
        "jvm_api_sha256": sha256(jvm_api),
        "klib_api_sha256": sha256(klib_api),
        "raw_source_source_sha256": sha256(source_raw.encode("utf-8")),
        "source_source_sha256": sha256(source_source.encode("utf-8")),
        "probe_source_sha256": sha256(PROBE.read_bytes()),
        "java_version": java_output,
        "reflection_stdout": result.stdout.strip(),
        "reflection_stdout_sha256": sha256(result.stdout.encode("utf-8")),
    }
    encoded = json.dumps(receipt, sort_keys=True, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    print(encoded, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
