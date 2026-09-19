#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$SCRIPT_DIR/benchmark_gate.sh"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-benchmark-gate-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

BASELINE="$TEMP_DIR/baseline.tsv"
MEASURED_PASS="$TEMP_DIR/measured-pass.tsv"
MEASURED_FAIL="$TEMP_DIR/measured-fail.tsv"
SUMMARY="$TEMP_DIR/summary.md"

cat >"$BASELINE" <<'EOF'
kind	case	metric	value_ms
execution	fixture	runtime_ms	100
compile	hello	TOTAL	200
EOF

cat >"$MEASURED_PASS" <<'EOF'
kind	case	metric	value_ms
execution	fixture	runtime_ms	109.99
compile	hello	TOTAL	220
EOF

if ! bash "$GATE" --compare-only --baseline "$BASELINE" --measured "$MEASURED_PASS" \
    --output "$TEMP_DIR/pass-report.tsv" --summary "$SUMMARY" --tolerance 10; then
    echo "FAIL: benchmark gate rejected measurements inside the tolerance" >&2
    exit 1
fi
grep -q $'execution\tfixture\truntime_ms\t100\t109.99' "$TEMP_DIR/pass-report.tsv"
grep -q 'Result: PASS' "$SUMMARY"

cat >"$MEASURED_FAIL" <<'EOF'
kind	case	metric	value_ms
execution	fixture	runtime_ms	111
compile	hello	TOTAL	200
EOF

if bash "$GATE" --compare-only --baseline "$BASELINE" --measured "$MEASURED_FAIL" \
    --output "$TEMP_DIR/fail-report.tsv" --summary "$TEMP_DIR/fail-summary.md" --tolerance 10; then
    echo "FAIL: benchmark gate accepted an intentional +11% regression" >&2
    exit 1
fi
grep -q $'execution\tfixture\truntime_ms\t100\t111' "$TEMP_DIR/fail-report.tsv"
grep -q $'\tFAIL$' "$TEMP_DIR/fail-report.tsv"
grep -q 'Result: FAIL' "$TEMP_DIR/fail-summary.md"

echo 'OK: benchmark gate enforces the configured tolerance and reports regressions'
