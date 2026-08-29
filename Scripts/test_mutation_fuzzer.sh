#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
# --generate-only never compiles, so STDLIB_ARGS is intentionally left out of
# run_generator() and the manifest-check heredoc below.
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
# Kept in sync by hand with the operations mutate_diff_cases.py can choose from.
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
  --workers 1

echo "Mutation fuzzer focused tests passed."
