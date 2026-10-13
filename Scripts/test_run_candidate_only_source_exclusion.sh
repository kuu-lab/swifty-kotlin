#!/usr/bin/env bash
# The artifact runner's .expected fallback must not claim source-only cases.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-candidate-discovery-test.XXXXXX")"
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
case "$(basename "$src")" in
  canonical.kt) expected=canonical ;;
  implicit.kt) expected=implicit ;;
  *) echo 'source-only case reached artifact compiler' >&2; exit 71 ;;
esac
printf '%s\n' '#!/usr/bin/env bash' "printf '$expected\\n'" >"$out"
chmod +x "$out"
EOF
chmod +x "$TEMP_DIR/kswiftc"
printf '// CANDIDATE-ONLY: canonical artifact case\nfun main() {}\n' >"$TEMP_DIR/cases/canonical.kt"
printf 'canonical\n' >"$TEMP_DIR/cases/canonical.expected.stdout"
printf 'fun main() {}\n' >"$TEMP_DIR/cases/implicit.kt"
printf 'implicit\n' >"$TEMP_DIR/cases/implicit.expected"
printf '// DIFF_CANDIDATE_ONLY_FROM_SOURCE: sidecar\nfun main() {}\n' >"$TEMP_DIR/cases/source_sidecar.kt"
printf 'source\n' >"$TEMP_DIR/cases/source_sidecar.expected"
printf '// DIFF_CANDIDATE_ONLY_FROM_SOURCE\n// EXPECT-STDOUT: source\nfun main() {}\n' >"$TEMP_DIR/cases/source_inline.kt"
set +e
KSWIFTC="$TEMP_DIR/kswiftc" DIFF_STDLIB_LIBRARY="$TEMP_DIR/stdlib" \
  DIFF_ARTIFACT_ROOT="$TEMP_DIR/artifacts" bash "$SCRIPT_DIR/run_candidate_only.sh" "$TEMP_DIR/cases" >"$TEMP_DIR/output.log" 2>&1
result=$?
set -e
fail() { echo "FAIL: $1" >&2; cat "$TEMP_DIR/output.log" >&2; exit 1; }
[[ "$result" -eq 0 ]] || fail 'source-only cases must be excluded from artifact discovery'
grep -qF 'Summary: total=2 failed=0 passed=2' "$TEMP_DIR/output.log" || fail 'must preserve canonical and implicit artifact cases'
if grep -q 'source_.*\.kt' "$TEMP_DIR/output.log"; then fail 'source-only case was discovered'; fi
echo 'OK: candidate artifact discovery excludes source-only cases'
