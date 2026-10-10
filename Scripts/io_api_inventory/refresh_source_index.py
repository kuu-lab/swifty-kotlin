#!/usr/bin/env python3
"""Regenerate the Kotlin PSI source catalog using the pinned compiler version."""

import argparse
import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
OUTPUT = HERE / "source-declarations.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kotlin-home", required=True, type=Path)
    parser.add_argument("--java", default="java")
    parser.add_argument("--jars-dir", type=Path, help="Also refresh exact JVM metadata from the two pinned jars")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    compiler = args.kotlin_home / "bin/kotlinc"
    compiler_jar = args.kotlin_home / "lib/kotlin-compiler.jar"
    metadata_jar = args.kotlin_home / "lib/kotlin-metadata-jvm.jar"
    version = subprocess.run([str(compiler), "-version"], check=True, capture_output=True, text=True)
    if "kotlinc-jvm 2.3.10 " not in version.stdout + version.stderr:
        raise SystemExit("The declaration catalog requires Kotlin 2.3.10")
    adapter = HERE / "ExtractSourceDeclarations.kt"
    jvm_adapter = HERE / "ExtractJvmDeclarations.kt"
    jvm_inputs = []
    if args.jars_dir:
        lock = json.loads((HERE / "upstream-lock.json").read_text(encoding="utf-8"))
        for artifact in lock["mavenArtifacts"]:
            path = args.jars_dir / artifact["url"].rsplit("/", 1)[-1]
            if hashlib.sha256(path.read_bytes()).hexdigest() != artifact["sha256"]:
                raise SystemExit("JVM jar hash mismatch: " + str(path))
            jvm_inputs.append(str(path))
    with tempfile.TemporaryDirectory(prefix="io-source-index-") as temporary:
        output_jar = Path(temporary) / "extractor.jar"
        adapters = [str(adapter)] + ([str(jvm_adapter)] if jvm_inputs else [])
        classpath = str(compiler_jar) + (os.pathsep + str(metadata_jar) if jvm_inputs else "")
        subprocess.run([str(compiler)] + adapters + ["-classpath", classpath, "-d", str(output_jar)], check=True)
        execution = subprocess.run([
            args.java, "-cp", str(output_jar) + os.pathsep + str(args.kotlin_home / "lib/*"),
            "ExtractSourceDeclarationsKt", str(REPO)
        ], check=True, capture_output=True, text=True)
        if jvm_inputs:
            jvm_execution = subprocess.run([
                args.java, "-cp", str(output_jar) + os.pathsep + str(args.kotlin_home / "lib/*"),
                "ExtractJvmDeclarationsKt"
            ] + jvm_inputs, check=True, capture_output=True, text=True)
    catalog = json.loads(execution.stdout)
    catalog["runtimeFiles"] = [
        {"path": path.relative_to(REPO).as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        for path in sorted((REPO / "Sources/Runtime").rglob("*.swift"))
    ]
    catalog["toolchain"] = {
        "kotlinVersion": "2.3.10",
        "compilerJarSha256": hashlib.sha256(compiler_jar.read_bytes()).hexdigest(),
        "extractorSha256": hashlib.sha256(adapter.read_bytes()).hexdigest(),
    }
    outputs = [(OUTPUT, catalog)]
    if jvm_inputs:
        jvm_catalog = json.loads(jvm_execution.stdout)
        jvm_catalog["toolchain"] = dict(catalog["toolchain"],
            metadataJarSha256=hashlib.sha256(metadata_jar.read_bytes()).hexdigest(),
            jvmExtractorSha256=hashlib.sha256(jvm_adapter.read_bytes()).hexdigest())
        outputs.append((HERE / "jvm-declarations.json", jvm_catalog))
    for path, data in outputs:
        rendered = (json.dumps(data, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
        if args.write:
            path.write_bytes(rendered)
        elif not path.is_file() or path.read_bytes() != rendered:
            raise SystemExit("Declaration catalog is stale: " + str(path) + "; regenerate with --write")
    lock_path = HERE / "upstream-lock.json"
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    for path, _ in outputs:
        digest_key = "sourceDeclarationsSha256" if path == OUTPUT else "jvmDeclarationsSha256"
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if args.write:
            lock[digest_key] = digest
        elif lock.get(digest_key) != digest:
            raise SystemExit("Declaration catalog lock mismatch: " + str(path))
    if args.write:
        lock_path.write_bytes((json.dumps(lock, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    print("OK source catalog: %d files, %d declarations" % (len(catalog["files"]), len(catalog["declarations"])))


if __name__ == "__main__":
    main()
