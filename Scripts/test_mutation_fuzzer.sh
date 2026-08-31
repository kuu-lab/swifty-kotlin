#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
STDLIB_ARGS=()
if [[ -n "${FUZZ_STDLIB_LIBRARY:-}" ]]; then
  STDLIB_ARGS=(--stdlib-library "$FUZZ_STDLIB_LIBRARY")
fi
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-mutation-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

run_generator() {
  local output_dir="$1"
  "$PYTHON_BIN" "$SCRIPT_DIR/mutate_diff_cases.py" \
    --seed-dir "$ROOT_DIR/Scripts/diff_cases" \
    --seed 23023 \
    --cases 24 \
    --duration-seconds 30 \
    --workers 1 \
    --generate-only \
    --output-dir "$output_dir"
}

run_generator "$TEMP_DIR/generated-a"
run_generator "$TEMP_DIR/generated-b"
diff -ru "$TEMP_DIR/generated-a" "$TEMP_DIR/generated-b"

"$PYTHON_BIN" - "$TEMP_DIR/generated-a/manifest.json" <<'PY'
import json
import sys

manifest = json.load(open(sys.argv[1], encoding="utf-8"))
operations = {entry["mutation"]["operation"] for entry in manifest}
expected = {"replace", "delete", "swap"}
missing = expected - operations
if missing:
    raise SystemExit(f"deterministic mutation smoke missed operations: {sorted(missing)}")
print(f"Deterministic mutation smoke: {len(manifest)} cases, operations={sorted(operations)}")
PY

"$PYTHON_BIN" "$SCRIPT_DIR/mutate_diff_cases.py" \
  --kswiftc "$KSWIFTC" \
  --replay-dir "$ROOT_DIR/Tests/CrashCorpus" \
  "${STDLIB_ARGS[@]}" \
  --timeout-seconds 30 \
  --workers 1

"$PYTHON_BIN" "$SCRIPT_DIR/mutate_diff_cases.py" \
  --kswiftc "$KSWIFTC" \
  --seed-dir "$ROOT_DIR/Scripts/diff_cases" \
  --seed 23023 \
  --cases 2 \
  --duration-seconds 90 \
  --timeout-seconds 30 \
  "${STDLIB_ARGS[@]}" \
  --workers 1 \
  --report "$TEMP_DIR/focused-report.json"

echo "Mutation fuzzer focused tests passed."
