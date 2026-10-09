#!/usr/bin/env bash
# Native-only failures must retain their artifact paths in parallel TSV reports.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-candidate-report-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/cases" "$TEMP_DIR/stdlib"
printf '{}\n' >"$TEMP_DIR/stdlib/manifest.json"

cat >"$TEMP_DIR/kswiftc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out="" src="" previous=""
for arg in "$@"; do
  [[ "$previous" != -o ]] || out="$arg"
  [[ "$arg" != *.kt ]] || src="$arg"
  previous="$arg"
done
if [[ "$src" == *native_compilefail.kt ]]; then
  echo 'fake candidate compile failure' >&2
  exit 42
fi
if [[ "$src" == *native_missing.kt ]]; then
  echo 'missing-oracle case must not reach compiler' >&2
  exit 93
fi
printf '%s\n' '#!/usr/bin/env bash' >"$out"
if [[ "$src" == *script_okcase.kt ]]; then
  printf '%s\n' "printf 'regular output\\n'" >>"$out"
else
  printf '%s\n' "printf 'native output\\n'" >>"$out"
fi
chmod +x "$out"
EOF
cat >"$TEMP_DIR/kotlinc" <<'EOF'
#!/usr/bin/env bash
previous="" script=""
for arg in "$@"; do
  [[ "$previous" != -script ]] || script="$arg"
  previous="$arg"
done
if [[ -z "$script" ]]; then
  [[ "$*" == *-version* ]] || exit 91
  exit 0
fi
[[ "$script" == *script_okcase.kts ]] || exit 92
printf 'regular output\n'
EOF
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$TEMP_DIR/java"
chmod +x "$TEMP_DIR/kswiftc" "$TEMP_DIR/kotlinc" "$TEMP_DIR/java"
for name in native_mismatch native_compilefail native_missing; do
  printf '// DIFF_CANDIDATE_ONLY\nfun main() {}\n' >"$TEMP_DIR/cases/$name.kt"
done
printf 'expected native output\n' >"$TEMP_DIR/cases/native_mismatch.expected"
printf 'native output\n' >"$TEMP_DIR/cases/native_compilefail.expected"
printf 'println("regular output")\n' >"$TEMP_DIR/cases/script_okcase.kt"

set +e
KSWIFTC="$TEMP_DIR/kswiftc" KOTLINC="$TEMP_DIR/kotlinc" JAVA_BIN="$TEMP_DIR/java" \
  DIFF_REQUIRE_JDK21=0 KOTLINC_REF_CACHE_DIR= DIFF_STDLIB_LIBRARY="$TEMP_DIR/stdlib" \
  DIFF_ARTIFACT_ROOT="$TEMP_DIR/artifacts" bash "$SCRIPT_DIR/diff_kotlinc.sh" \
  --parallel --jobs 2 --report "$TEMP_DIR/report.tsv" "$TEMP_DIR/cases" >"$TEMP_DIR/output.log" 2>&1
result=$?
set -e
fail() { echo "FAIL: $1" >&2; cat "$TEMP_DIR/output.log" "$TEMP_DIR/report.tsv" >&2; exit 1; }
[[ "$result" -eq 1 ]] || fail 'a directory containing native failures must exit 1'
grep -qF 'Summary: total=4 failed=3 passed=1 skipped=0' "$TEMP_DIR/output.log" || fail 'wrong directory summary'
for name in native_mismatch native_compilefail native_missing; do
  artifact="$(awk -F '\t' -v path="$TEMP_DIR/cases/$name.kt" '$1 == path && $2 == "FAIL" { print $3 }' "$TEMP_DIR/report.tsv")"
  [[ -n "$artifact" && -f "$artifact/summary.txt" ]] || fail "$name must expose a persisted artifact directory"
done
artifact="$(awk -F '\t' -v path="$TEMP_DIR/cases/native_mismatch.kt" '$1 == path { print $3 }' "$TEMP_DIR/report.tsv")"
[[ -s "$artifact/stdout.diff" ]] || fail 'stdout mismatch must have a nonempty diff artifact'
grep -qF 'Candidate-only case is missing its expected output file:' "$TEMP_DIR/output.log" || fail 'missing oracle must be diagnosed'
artifact="$(awk -F '\t' -v path="$TEMP_DIR/cases/native_missing.kt" '$1 == path { print $3 }' "$TEMP_DIR/report.tsv")"
grep -qF 'candidate_compile_exit: not-run' "$artifact/summary.txt" || fail 'missing-oracle case must not be compiled'
grep -qF 'candidate_run_exit: not-run' "$artifact/summary.txt" || fail 'missing-oracle case must not be executed'
echo 'OK: parallel candidate-only TSV reports retain failure artifacts'
