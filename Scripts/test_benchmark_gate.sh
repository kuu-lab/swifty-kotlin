#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$SCRIPT_DIR/benchmark_gate.sh"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-benchmark-gate-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

BASELINE="$TEMP_DIR/baseline.tsv"
MEASURED_PASS="$TEMP_DIR/measured-pass.tsv"
MEASURED_IMPROVEMENT="$TEMP_DIR/measured-improvement.tsv"
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

cat >"$MEASURED_IMPROVEMENT" <<'EOF'
kind	case	metric	value_ms
execution	fixture	runtime_ms	75
compile	hello	TOTAL	150
EOF

if ! bash "$GATE" --compare-only --baseline "$BASELINE" --measured "$MEASURED_IMPROVEMENT" \
    --output "$TEMP_DIR/improvement-report.tsv" --summary "$TEMP_DIR/improvement-summary.md" --tolerance 10; then
    echo "FAIL: benchmark gate rejected an improvement" >&2
    exit 1
fi
grep -q $'execution\tfixture\truntime_ms\t100\t75\t-25.00\t-25.000\tPASS' "$TEMP_DIR/improvement-report.tsv"
grep -q 'Regression tolerance: +10%' "$TEMP_DIR/improvement-summary.md"
grep -q 'Result: PASS' "$TEMP_DIR/improvement-summary.md"

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

cat >"$TEMP_DIR/rounding-fail.tsv" <<'EOF'
kind	case	metric	value_ms
execution	fixture	runtime_ms	110.004
compile	hello	TOTAL	200
EOF
if bash "$GATE" --compare-only --baseline "$BASELINE" --measured "$TEMP_DIR/rounding-fail.tsv" \
    --output "$TEMP_DIR/rounding-fail-report.tsv" --tolerance 10; then
    echo "FAIL: benchmark gate accepted a +10.004% regression" >&2
    exit 1
fi
grep -q $'execution\tfixture\truntime_ms\t100\t110.004\t10.00\t10.004\tFAIL' "$TEMP_DIR/rounding-fail-report.tsv"

cat >"$TEMP_DIR/missing-execution-baseline.tsv" <<'EOF'
kind	case	metric	value_ms
compile	hello	TOTAL	200
EOF
if bash "$GATE" --compare-only --baseline "$TEMP_DIR/missing-execution-baseline.tsv" --measured "$MEASURED_PASS" \
    --output "$TEMP_DIR/missing-execution-baseline-report.tsv" --tolerance 10; then
    echo "FAIL: benchmark gate treated an execution metric without a baseline as diagnostic" >&2
    exit 1
fi

cat >"$TEMP_DIR/missing-measured.tsv" <<'EOF'
kind	case	metric	value_ms
compile	hello	TOTAL	200
EOF
if bash "$GATE" --compare-only --baseline "$BASELINE" --measured "$TEMP_DIR/missing-measured.tsv" \
    --output "$TEMP_DIR/missing-measured-report.tsv" --tolerance 10; then
    echo "FAIL: benchmark gate accepted a missing enforced measurement" >&2
    exit 1
fi

FAKE_COMPILER="$TEMP_DIR/fake-kswiftc"
cat >"$FAKE_COMPILER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output=""
emit=""
while (($# > 0)); do
    case "$1" in
        --emit)
            emit="$2"
            shift 2
            ;;
        -o)
            output="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [[ "$emit" == "executable" ]]; then
    printf '#!/usr/bin/env bash\nsleep 0.01\n' >"$output"
    chmod +x "$output"
else
    : >"$output"
    printf 'Parse 1.00\nTOTAL 2.00\n' >&2
fi
EOF
chmod +x "$FAKE_COMPILER"

PRODUCTION_BASELINE_8="$TEMP_DIR/production-baseline-8.tsv"
cat >"$PRODUCTION_BASELINE_8" <<'EOF'
kind	case	metric	value_ms
execution	compile_medium	runtime_ms	12
execution	filter	runtime_ms	1900
execution	for_in_range	runtime_ms	170
execution	map	runtime_ms	6500
execution	sort	runtime_ms	31000
compile	hello	TOTAL	2000
compile	medium	TOTAL	2050
compile	stdlib-only	TOTAL	12000
EOF
if KSWIFTC="$FAKE_COMPILER" bash "$GATE" --baseline "$PRODUCTION_BASELINE_8" \
    --output "$TEMP_DIR/production-8-report.tsv" --execution-runs 1 --compile-runs 1 \
    >"$TEMP_DIR/production-8.log" 2>&1; then
    echo "FAIL: production benchmark gate accepted an 8-key baseline" >&2
    exit 1
fi
grep -q 'error: production benchmark baseline is missing required metric: execution/arch010_hash_collections/runtime_ms' "$TEMP_DIR/production-8.log"
grep -q 'error: production benchmark baseline must contain exactly 9 metrics, got 8' "$TEMP_DIR/production-8.log"

KSWIFTC="$FAKE_COMPILER" bash "$GATE" --measure-only --measure-case execution/filter \
    --baseline "$BASELINE" --output "$TEMP_DIR/filtered-execution.tsv" --execution-runs 2 --compile-runs 1
grep -Eq $'^execution\tfilter\truntime_ms\t[0-9]+\.[0-9]{3}$' "$TEMP_DIR/filtered-execution.tsv"
[[ "$(awk 'END { print NR }' "$TEMP_DIR/filtered-execution.tsv")" == "2" ]]

KSWIFTC="$FAKE_COMPILER" bash "$GATE" --measure-only --measure-case compile/hello \
    --baseline "$BASELINE" --output "$TEMP_DIR/filtered-compile.tsv" --execution-runs 1 --compile-runs 1
grep -q $'compile\thello\tParse\t1.00' "$TEMP_DIR/filtered-compile.tsv"
grep -q $'compile\thello\tTOTAL\t2.00' "$TEMP_DIR/filtered-compile.tsv"
if grep -q $'compile\tmedium\t' "$TEMP_DIR/filtered-compile.tsv"; then
    echo "FAIL: --measure-case compiled an unselected case" >&2
    exit 1
fi

echo 'OK: benchmark gate accepts improvements, reports regressions, and fails closed on enforced metrics'
