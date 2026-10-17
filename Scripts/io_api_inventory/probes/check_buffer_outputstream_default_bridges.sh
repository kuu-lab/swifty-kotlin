#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
JAR_PATH="${1:-${KOTLINC_KOTLINX_IO_JAR:-$ROOT_DIR/.runtime-build/deps/kotlinx-io-core-jvm-0.9.1.jar}}"

if [[ ! -f "$JAR_PATH" ]]; then
  printf 'Missing pinned kotlinx-io JVM jar: %s\n' "$JAR_PATH" >&2
  exit 2
fi

expected_sha256="$(python3 - "$ROOT_DIR/Scripts/io_api_inventory/upstream-lock.json" <<'PY'
import json
import sys

lock = json.load(open(sys.argv[1], encoding="utf-8"))
matches = [entry for entry in lock["mavenArtifacts"]
           if entry["coordinate"] == "org.jetbrains.kotlinx:kotlinx-io-core-jvm:0.9.1"]
if len(matches) != 1:
    raise SystemExit("Expected exactly one locked kotlinx-io-core-jvm:0.9.1 artifact")
print(matches[0]["sha256"])
PY
)"
actual_sha256="$(python3 - "$JAR_PATH" <<'PY'
import hashlib
import sys

digest = hashlib.sha256()
with open(sys.argv[1], "rb") as artifact:
    for chunk in iter(lambda: artifact.read(1024 * 1024), b""):
        digest.update(chunk)
print(digest.hexdigest())
PY
)"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  printf 'Pinned JVM jar hash mismatch: expected %s, got %s\n' "$expected_sha256" "$actual_sha256" >&2
  exit 1
fi

probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/kuu2637-jvm-probe.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
javac -classpath "$JAR_PATH" -d "$probe_dir" "$SCRIPT_DIR/BufferOutputStreamDefaultBridgeAbi.java"
java -classpath "$probe_dir:$JAR_PATH" BufferOutputStreamDefaultBridgeAbi
