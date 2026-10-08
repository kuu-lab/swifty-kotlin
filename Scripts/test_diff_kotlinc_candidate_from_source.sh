#!/usr/bin/env bash
# Exercise the real runners without a JVM or compiler build.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-source-candidate-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/cases" "$TEMP_DIR/stdlib"
printf '{}\n' >"$TEMP_DIR/stdlib/manifest.json"

cat >"$TEMP_DIR/kswiftc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out="" src="" previous="" from_source=0
for arg in "$@"; do
  [[ "$previous" != "-o" ]] || out="$arg"
  [[ "$arg" != *.kt ]] || src="$arg"
  [[ "$arg" != "--stdlib-from-source" ]] || from_source=1
  previous="$arg"
done
case "$(basename "$src")" in
  source_*)
    [[ "$from_source" -eq 1 ]] || { echo 'missing --stdlib-from-source' >&2; exit 71; }
    ;;
  canonical.kt)
    [[ "$from_source" -eq 0 ]] || { echo 'artifact case compiled from source' >&2; exit 72; }
    ;;
  *) echo "unexpected compiler input: $src" >&2; exit 73 ;;
esac
printf '%s\n' '#!/usr/bin/env bash' >"$out"
case "$(basename "$src")" in
  source_inline.kt) printf '%s\n' "printf 'first\\n\\nlast\\n'" >>"$out" ;;
  source_*) printf '%s\n' "printf 'sidecar output\\n'" >>"$out" ;;
  canonical.kt) printf '%s\n' "printf 'canonical output\\n'" >>"$out" ;;
esac
chmod +x "$out"
EOF
chmod +x "$TEMP_DIR/kswiftc"
printf '// DIFF_CANDIDATE_ONLY_FROM_SOURCE: sidecar oracle\nfun main() {}\n' >"$TEMP_DIR/cases/source_sidecar.kt"
printf 'sidecar output\n' >"$TEMP_DIR/cases/source_sidecar.expected"
printf '// DIFF_CANDIDATE_ONLY_FROM_SOURCE\n// EXPECT-STDOUT: first\n// EXPECT-STDOUT:\n// EXPECT-STDOUT: last\nfun main() {}\n' >"$TEMP_DIR/cases/source_inline.kt"
printf '// CANDIDATE-ONLY: artifact oracle\nfun main() {}\n' >"$TEMP_DIR/cases/canonical.kt"
printf 'canonical output\n' >"$TEMP_DIR/cases/canonical.expected.stdout"
printf '// SKIP-DIFF (DEBT-DIFF-001): unrelated skipped case\nfun main() {}\n' >"$TEMP_DIR/cases/skipped.kt"

export KSWIFTC="$TEMP_DIR/kswiftc" KOTLINC="$TEMP_DIR/missing-kotlinc" JAVA_BIN="$TEMP_DIR/missing-java"
export DIFF_REQUIRE_JDK21=1 DIFF_STDLIB_LIBRARY="$TEMP_DIR/stdlib"
export DIFF_ARTIFACT_ROOT="$TEMP_DIR/artifacts" DIFF_LOG_PASS=1

fail() {
  echo "FAIL: $1" >&2
  cat "$TEMP_DIR/"*.log >&2
  exit 1
}
for mode in serial parallel; do
  args=(--no-parallel)
  [[ "$mode" != parallel ]] || args=(--parallel --jobs 2)
  bash "$SCRIPT_DIR/diff_kotlinc.sh" "${args[@]}" --report "$TEMP_DIR/$mode.tsv" "$TEMP_DIR/cases" >"$TEMP_DIR/$mode.log" 2>&1 || fail "$mode source cases must run without JVM tooling"
  grep -qF 'Summary: total=2 failed=0 passed=2 skipped=2' "$TEMP_DIR/$mode.log" || fail "$mode classification summary"
  for name in source_sidecar source_inline; do
    grep -qF "PASS $TEMP_DIR/cases/$name.kt" "$TEMP_DIR/$mode.log" || fail "$mode did not execute $name"
  done
  grep -qF "SKIP $TEMP_DIR/cases/canonical.kt (candidate-only; run Scripts/run_candidate_only.sh)" "$TEMP_DIR/$mode.log" || fail "$mode must preserve the canonical lane"
done

bash "$SCRIPT_DIR/run_candidate_only.sh" "$TEMP_DIR/cases" >"$TEMP_DIR/canonical.log" 2>&1 || fail 'canonical discovery must exclude source-only cases'
grep -qF 'Summary: total=1 failed=0 passed=1' "$TEMP_DIR/canonical.log" || fail 'canonical runner must execute only its own case'
grep -qF "PASS $TEMP_DIR/cases/canonical.kt" "$TEMP_DIR/canonical.log" || fail 'canonical case did not run'

DIFF_STDLIB_LIBRARY= bash "$SCRIPT_DIR/diff_kotlinc.sh" --candidate-only "$TEMP_DIR/cases/source_sidecar.kt" >"$TEMP_DIR/explicit.log" 2>&1 || fail 'explicit source mode must remain supported'
grep -qF "PASS $TEMP_DIR/cases/source_sidecar.kt" "$TEMP_DIR/explicit.log" || fail 'explicit source mode did not run'

mkdir -p "$TEMP_DIR/failure"
cp "$TEMP_DIR/cases/source_sidecar.kt" "$TEMP_DIR/failure/source_mismatch.kt"
printf 'different expected output\n' >"$TEMP_DIR/failure/source_mismatch.expected"
if bash "$SCRIPT_DIR/diff_kotlinc.sh" --parallel --jobs 2 --report "$TEMP_DIR/failure.tsv" "$TEMP_DIR/failure" >"$TEMP_DIR/failure.log" 2>&1; then
  fail 'source stdout mismatch must fail'
fi
artifact="$(awk -F '\t' '$2 == "FAIL" { print $3 }' "$TEMP_DIR/failure.tsv")"
[[ -n "$artifact" && -f "$artifact/summary.txt" && -s "$artifact/stdout.diff" ]] || fail 'parallel source failure must expose its artifact path and stdout diff'
echo 'OK: source candidate-only discovery, execution, and artifacts are correct'
