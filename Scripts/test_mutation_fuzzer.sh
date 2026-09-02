#!/usr/bin/env bash
set -euo pipefail

# Smoke-tests the mutation generator itself (determinism + operation
# coverage). Compiling generated/corpus cases against kswiftc is the nightly
# workflow's job (nightly-mutation-fuzzer.yml) — its "Replay committed crash
# corpus" and "Run bounded mutation fuzzer" steps already cover that ground,
# so this script stays generator-only and needs no kswiftc/stdlib inputs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-mutation-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

run_generator() {
  local output_dir="$1"
  "$PYTHON_BIN" "$SCRIPT_DIR/mutate_diff_cases.py" \
    --seed-dir "$SCRIPT_DIR/diff_cases" \
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

echo "Mutation generator smoke test passed."
