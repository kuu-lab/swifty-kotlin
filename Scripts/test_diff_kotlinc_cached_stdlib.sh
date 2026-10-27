#!/usr/bin/env bash
# Exercise cache selection and fallback without a compiler or stdlib build.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-diff-cache-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/cases" "$TEST_DIR/cached artifact" "$TEST_DIR/explicit"
printf '{}\n' > "$TEST_DIR/cached artifact/manifest.json"
printf '{}\n' > "$TEST_DIR/explicit/manifest.json"
cat > "$TEST_DIR/kswiftc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'socket:%s\n' "${KSWIFTK_DAEMON_SOCKET:-unset}" >> "$FAKE_LOG"
case "${1:-}" in
  --help)
    [[ "${FAKE_CACHE_MODE:-ok}" != unsupported ]] || exit 0
    printf '  --cached-stdlib-path   resolve cache\n'
    exit 0 ;;
  --cached-stdlib-path)
    printf 'resolve\n' >> "$FAKE_LOG"
    case "${FAKE_CACHE_MODE:-ok}" in
      unavailable) exit 2 ;;
      error) echo 'fake cache failure' >&2; exit 1 ;;
      invalid) echo '/missing/artifact'; exit 0 ;;
      *) printf '%s\n' "$FAKE_CACHED_PATH"; exit 0 ;;
    esac ;;
esac
out="" previous="" stdlib=0
for arg in "$@"; do
  [[ "$previous" != -o ]] || out="$arg"
  [[ "$arg" != --stdlib-only ]] || stdlib=1
  previous="$arg"
done
if (( stdlib )); then
  printf 'fresh\n' >> "$FAKE_LOG"
  mkdir -p "$out"
  printf '{}\n' > "$out/manifest.json"
else
  printf 'compile\n' >> "$FAKE_LOG"
  printf '%s\n' '#!/usr/bin/env bash' "printf 'OK\\n'" > "$out"
  chmod +x "$out"
fi
EOF
cat > "$TEST_DIR/timeout" <<'EOF'
#!/usr/bin/env bash
shift
exec "$@"
EOF
chmod +x "$TEST_DIR/kswiftc" "$TEST_DIR/timeout"
printf '// DIFF_CANDIDATE_ONLY\n// DIFF_EXPECT_OUTPUT: OK\nfun main() {}\n' > "$TEST_DIR/cases/diff.kt"
printf '// CANDIDATE-ONLY: artifact path\nfun main() {}\n' > "$TEST_DIR/cases/delegated.kt"
printf 'OK\n' > "$TEST_DIR/cases/delegated.expected.stdout"

run_diff() {
  : > "$TEST_DIR/log"
  env -u DIFF_STDLIB_LIBRARY -u KSWIFTK_STDLIB_LIBRARY -u DIFF_REUSE_STDLIB_CACHE -u FAKE_CACHE_MODE \
    -u DIFF_USE_DAEMON -u KSWIFTK_DAEMON_SOCKET \
    KSWIFTC="$TEST_DIR/kswiftc" TIMEOUT="$TEST_DIR/timeout" FAKE_LOG="$TEST_DIR/log" \
    FAKE_CACHED_PATH="$TEST_DIR/cached artifact" DIFF_ARTIFACT_ROOT="$TEST_DIR/artifacts" \
    "$@" > "$TEST_DIR/output" 2>&1
}
fail() { cat "$TEST_DIR/output" "$TEST_DIR/log" >&2; echo "FAIL: $1" >&2; exit 1; }

for case in diff delegated; do
  run_diff bash "$SCRIPT_DIR/diff_kotlinc.sh" --no-parallel "$TEST_DIR/cases/$case.kt" || fail "$case cached run"
  grep -qx resolve "$TEST_DIR/log" || fail "$case did not resolve the cache"
  grep -qx 'socket:/dev/null/kswiftk-diff-no-daemon' "$TEST_DIR/log" || fail "$case must bypass the global daemon"
  if grep -qx fresh "$TEST_DIR/log"; then fail "$case rebuilt the stdlib"; fi
  grep -qF 'Using validated stdlib artifact:' "$TEST_DIR/output" || fail "$case did not report reuse"
done
run_diff DIFF_USE_DAEMON=1 KSWIFTK_DAEMON_SOCKET="$TEST_DIR/daemon.sock" bash "$SCRIPT_DIR/diff_kotlinc.sh" --no-parallel "$TEST_DIR/cases/diff.kt" || fail 'daemon opt-in'
grep -qx "socket:$TEST_DIR/daemon.sock" "$TEST_DIR/log" || fail 'daemon socket must be preserved when opted in'
grep -qx fresh "$TEST_DIR/log" || fail 'daemon opt-in must build a fresh artifact'
if grep -qx resolve "$TEST_DIR/log"; then fail 'daemon opt-in must bypass the local compiler cache'; fi
run_diff DIFF_STDLIB_LIBRARY="$TEST_DIR/explicit" bash "$SCRIPT_DIR/diff_kotlinc.sh" --no-parallel "$TEST_DIR/cases/diff.kt" || fail 'explicit artifact'
if grep -qx resolve "$TEST_DIR/log"; then fail 'explicit artifact must take precedence'; fi
run_diff DIFF_REUSE_STDLIB_CACHE=0 bash "$SCRIPT_DIR/diff_kotlinc.sh" --no-parallel "$TEST_DIR/cases/diff.kt" || fail 'fresh artifact'
grep -qx fresh "$TEST_DIR/log" || fail 'fresh artifact option was ignored'
if grep -qx resolve "$TEST_DIR/log"; then fail 'fresh mode must bypass cache'; fi
for mode in unavailable unsupported; do
  run_diff FAKE_CACHE_MODE="$mode" bash "$SCRIPT_DIR/diff_kotlinc.sh" --no-parallel "$TEST_DIR/cases/diff.kt" || fail "$mode fallback"
  grep -qx fresh "$TEST_DIR/log" || fail "$mode must build a fresh artifact"
done
for mode in error invalid; do
  if run_diff FAKE_CACHE_MODE="$mode" bash "$SCRIPT_DIR/diff_kotlinc.sh" --no-parallel "$TEST_DIR/cases/diff.kt"; then
    fail "$mode must not succeed"
  fi
  if grep -qx fresh "$TEST_DIR/log"; then fail "$mode must not trigger a second build"; fi
done
echo 'PASS: validated diff stdlib cache selection and fallback'
