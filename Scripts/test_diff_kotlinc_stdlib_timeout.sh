#!/usr/bin/env bash
# Check stdlib-specific timeouts without compiling the real stdlib.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-stdlib-timeout.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/cases"

cat > "$TEST_DIR/timeout" <<'EOF'
#!/usr/bin/env bash
limit="$1"
shift
if [[ "${2:-}" == --stdlib-only ]]; then
  printf 'stdlib:%s\n' "$limit" >> "$TIMEOUT_LOG"
  if [[ "${FAKE_STDLIB_EXIT:-0}" != 0 ]]; then
    printf 'fake stdlib diagnostic\n' >&2
    exit "$FAKE_STDLIB_EXIT"
  fi
fi
exec "$@"
EOF
cat > "$TEST_DIR/kswiftc" <<'EOF'
#!/usr/bin/env bash
out="" previous="" stdlib=0
for arg in "$@"; do
  [[ "$previous" != -o ]] || out="$arg"
  [[ "$arg" != --stdlib-only ]] || stdlib=1
  previous="$arg"
done
if (( stdlib )); then
  mkdir -p "$out"
  printf '{}\n' > "$out/manifest.json"
else
  printf '%s\n' '#!/usr/bin/env bash' "printf 'OK\\n'" > "$out"
  chmod +x "$out"
fi
EOF
chmod +x "$TEST_DIR/timeout" "$TEST_DIR/kswiftc"
printf '// DIFF_CANDIDATE_ONLY\n// DIFF_EXPECT_OUTPUT: OK\nfun main() {}\n' > "$TEST_DIR/cases/diff.kt"
printf '// CANDIDATE-ONLY: artifact path\nfun main() {}\n' > "$TEST_DIR/cases/delegated.kt"
printf 'OK\n' > "$TEST_DIR/cases/delegated.expected.stdout"

run_diff() {
  : > "$TEST_DIR/timeouts"
  env -u DIFF_STDLIB_COMPILE_TIMEOUT -u FAKE_STDLIB_EXIT \
    KSWIFTC="$TEST_DIR/kswiftc" TIMEOUT="$TEST_DIR/timeout" \
    TIMEOUT_LOG="$TEST_DIR/timeouts" DIFF_ARTIFACT_ROOT="$TEST_DIR/artifacts" \
    "$@" > "$TEST_DIR/output" 2>&1
}
fail() { cat "$TEST_DIR/output" "$TEST_DIR/timeouts" >&2; echo "FAIL: $1" >&2; exit 1; }

run_diff bash "$SCRIPT_DIR/diff_kotlinc.sh" --no-parallel --compile-timeout 5 "$TEST_DIR/cases/diff.kt" || fail 'default build'
grep -qx 'stdlib:600' "$TEST_DIR/timeouts" || fail 'stdlib default must not use the case timeout'
grep -qF 'Compile timeout: 5s' "$TEST_DIR/output" || fail 'case timeout changed'
run_diff DIFF_STDLIB_COMPILE_TIMEOUT=23 bash "$SCRIPT_DIR/diff_kotlinc.sh" --no-parallel "$TEST_DIR/cases/diff.kt" || fail 'environment override'
grep -qx 'stdlib:23' "$TEST_DIR/timeouts" || fail 'environment timeout not passed'
run_diff DIFF_STDLIB_COMPILE_TIMEOUT=23 bash "$SCRIPT_DIR/diff_kotlinc.sh" --no-parallel --stdlib-timeout=31 "$TEST_DIR/cases/diff.kt" || fail 'CLI override'
grep -qx 'stdlib:31' "$TEST_DIR/timeouts" || fail 'CLI timeout must override environment'
run_diff bash "$SCRIPT_DIR/diff_kotlinc.sh" --stdlib-timeout 47 "$TEST_DIR/cases/delegated.kt" || fail 'candidate-only delegation'
grep -qx 'stdlib:47' "$TEST_DIR/timeouts" || fail 'delegated timeout not forwarded'
if run_diff FAKE_STDLIB_EXIT=124 bash "$SCRIPT_DIR/diff_kotlinc.sh" --no-parallel --stdlib-timeout 9 "$TEST_DIR/cases/diff.kt"; then
  fail 'timeout must fail the run'
fi
grep -qF 'timed out after 9s' "$TEST_DIR/output" || fail 'timeout diagnostic missing'
if run_diff FAKE_STDLIB_EXIT=37 bash "$SCRIPT_DIR/diff_kotlinc.sh" --no-parallel "$TEST_DIR/cases/diff.kt"; then
  fail 'compiler failure must fail the run'
fi
grep -qF 'Failed to build stdlib artifact: exit=37' "$TEST_DIR/output" || fail 'compiler exit missing'
grep -qF 'fake stdlib diagnostic' "$TEST_DIR/output" || fail 'compiler diagnostic missing'
if run_diff bash "$SCRIPT_DIR/diff_kotlinc.sh" --stdlib-timeout=0 "$TEST_DIR/cases/diff.kt"; then
  fail 'invalid timeout must fail'
fi
grep -qF 'stdlib timeout must be a positive integer' "$TEST_DIR/output" || fail 'invalid timeout diagnostic missing'
echo 'PASS: independent stdlib timeout and failure diagnostics'
