#!/usr/bin/env bash
# Regression test for diff_kotlinc.sh candidate-only execution and expected
# stdout comparison.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-diff-candidate-only-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

FAKE_BIN_DIR="$TEMP_DIR/fake_bin"
mkdir -p "$FAKE_BIN_DIR"

cat >"$FAKE_BIN_DIR/fake_kotlinc" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$KOTLINC_LOG"
if [[ "${1:-}" == "-version" ]]; then
  echo "fake kotlinc"
  exit 0
fi
echo "Reference compilation must not run for candidate-only cases." >&2
exit 80
EOF
chmod +x "$FAKE_BIN_DIR/fake_kotlinc"

cat >"$FAKE_BIN_DIR/fake_kswiftc" <<'EOF'
#!/usr/bin/env bash
out=""
src=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-o" ]]; then
    out="$arg"
  fi
  if [[ "$arg" == *.kt ]]; then
    src="$arg"
  fi
  prev="$arg"
done
if [[ -z "$out" ]]; then
  echo "fake kswiftc"
  exit 0
fi
case "$(basename "$src")" in
  candidate_only_pass.kt)
    cat >"$out" <<'PROGRAM'
#!/usr/bin/env bash
printf 'first\nsecond\n'
PROGRAM
    ;;
  candidate_only_mismatch.kt)
    cat >"$out" <<'PROGRAM'
#!/usr/bin/env bash
printf 'actual\n'
PROGRAM
    ;;
  *)
    echo "fake_kswiftc: unrecognized source fixture: $src" >&2
    exit 91
    ;;
esac
chmod +x "$out"
EOF
chmod +x "$FAKE_BIN_DIR/fake_kswiftc"

FAKE_STDLIB_DIR="$TEMP_DIR/fake_stdlib"
mkdir -p "$FAKE_STDLIB_DIR"
echo '{}' >"$FAKE_STDLIB_DIR/manifest.json"

CASES_DIR="$TEMP_DIR/cases"
mkdir -p "$CASES_DIR"
cat >"$CASES_DIR/candidate_only_pass.kt" <<'KOTLIN'
// DIFF_CANDIDATE_ONLY
// DIFF_EXPECT_OUTPUT: first
// DIFF_EXPECT_OUTPUT: second
fun main() {}
KOTLIN
cat >"$CASES_DIR/candidate_only_mismatch.kt" <<'KOTLIN'
// DIFF_CANDIDATE_ONLY
// DIFF_EXPECT_OUTPUT: expected
fun main() {}
KOTLIN

KOTLINC_LOG="$TEMP_DIR/kotlinc.log"
OUTPUT_LOG="$TEMP_DIR/output.log"

set +e
KOTLINC="$FAKE_BIN_DIR/fake_kotlinc" \
KSWIFTC="$FAKE_BIN_DIR/fake_kswiftc" \
DIFF_STDLIB_LIBRARY="$FAKE_STDLIB_DIR" \
DIFF_REQUIRE_JDK21=0 \
DIFF_ARTIFACT_ROOT="$TEMP_DIR/artifacts" \
KOTLINC_LOG="$KOTLINC_LOG" \
bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" --no-parallel "$CASES_DIR" >"$OUTPUT_LOG" 2>&1
diff_exit=$?
set -e

fail() {
  echo "FAIL: $1" >&2
  echo "--- diff_kotlinc.sh output ---" >&2
  cat "$OUTPUT_LOG" >&2
  exit 1
}

if [[ $diff_exit -eq 0 ]]; then
  fail "the expected-output mismatch fixture should make the diff run fail"
fi
if ! grep -qF "PASS $CASES_DIR/candidate_only_pass.kt (candidate-only)" "$OUTPUT_LOG"; then
  fail "candidate-only case with matching multiline stdout should PASS"
fi
if ! grep -qF "FAIL $CASES_DIR/candidate_only_mismatch.kt (candidate-only)" "$OUTPUT_LOG"; then
  fail "candidate-only case with mismatching stdout should FAIL"
fi
if ! grep -q "candidate-only stdout mismatch" "$OUTPUT_LOG"; then
  fail "candidate-only failure should explain the expected-output mismatch"
fi
if grep -Eq '\.kt([[:space:]]|$)' "$KOTLINC_LOG"; then
  fail "candidate-only fixtures must not be compiled by kotlinc"
fi
if ! grep -q "candidate-only" "$TEMP_DIR/artifacts"/*/summary.txt; then
  fail "candidate-only failure artifacts should identify the execution mode"
fi

echo "OK: diff_kotlinc.sh candidate-only execution and expected stdout comparison work"
