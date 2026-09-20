#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PAIRED_GATE="$SCRIPT_DIR/paired_benchmark_gate.sh"
REAL_GATE="$SCRIPT_DIR/benchmark_gate.sh"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-paired-benchmark-gate-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

BASE_COMPILER="$TEMP_DIR/base-kswiftc"
CANDIDATE_COMPILER="$TEMP_DIR/candidate-kswiftc"
FAKE_GATE="$TEMP_DIR/fake-benchmark-gate.sh"
BASELINE="$TEMP_DIR/baseline.tsv"
SEQUENCE_LOG="$TEMP_DIR/sequence.log"

printf '#!/usr/bin/env bash\nexit 0\n' >"$BASE_COMPILER"
printf '#!/usr/bin/env bash\nexit 0\n' >"$CANDIDATE_COMPILER"
chmod +x "$BASE_COMPILER" "$CANDIDATE_COMPILER"

cat >"$BASELINE" <<'EOF'
kind	case	metric	value_ms
execution	arch010_hash_collections	runtime_ms	100
execution	compile_medium	runtime_ms	100
execution	filter	runtime_ms	100
execution	for_in_range	runtime_ms	100
execution	map	runtime_ms	100
execution	sort	runtime_ms	100
compile	hello	TOTAL	200
compile	medium	TOTAL	200
compile	stdlib-only	TOTAL	200
EOF

cat >"$FAKE_GATE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mode="run"
output=""
measure_case=""
args=("$@")
while (($# > 0)); do
    case "$1" in
        --measure-only)
            mode="measure"
            shift
            ;;
        --measure-case)
            measure_case="$2"
            shift 2
            ;;
        --compare-only)
            mode="compare"
            shift
            ;;
        --output)
            output="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [[ "$mode" == "compare" ]]; then
    exec bash "$REAL_GATE" "${args[@]}"
fi
[[ "$mode" == "measure" && -n "$measure_case" && -n "$output" ]]

compiler="$(basename "$KSWIFTC")"
printf '%s\t%s\n' "$measure_case" "$compiler" >>"$SEQUENCE_LOG"
call="$(awk -F '\t' -v key="$measure_case" '$1 == key { count++ } END { print count }' "$SEQUENCE_LOG")"
block=$(( (call - 1) / 4 + 1 ))
position=$(( (call - 1) % 4 + 1 ))

case "$position" in
    1) drift=100 ;;
    2) drift=110 ;;
    3) drift=121 ;;
    4) drift=133.1 ;;
esac

multiplier=1
if [[ "$compiler" == "candidate-kswiftc" ]]; then
    case "${FAKE_SCENARIO:-drift}" in
        drift) multiplier=1 ;;
        regression) multiplier=1.15 ;;
        any-pass)
            if [[ "$block" == "1" ]]; then multiplier=1; else multiplier=1.15; fi
            ;;
        outlier)
            if [[ "$block" == "1" ]]; then multiplier=2; else multiplier=1; fi
            ;;
        boundary) multiplier=1.10 ;;
        over-boundary) multiplier=1.1001 ;;
        missing|duplicate|nonnumeric|mismatch) multiplier=1 ;;
        *) echo "unexpected fake scenario: $FAKE_SCENARIO" >&2; exit 1 ;;
    esac
fi

value="$(awk -v drift="$drift" -v multiplier="$multiplier" 'BEGIN { printf "%.6f", drift * multiplier }')"
kind="${measure_case%%/*}"
case_name="${measure_case#*/}"
mkdir -p "$(dirname "$output")"
printf 'kind\tcase\tmetric\tvalue_ms\n' >"$output"

if [[ "${FAKE_SCENARIO:-drift}" == "missing" && "$call" == "1" ]]; then
    exit 0
fi
if [[ "${FAKE_SCENARIO:-drift}" == "nonnumeric" && "$call" == "1" ]]; then
    value=not-a-number
fi
if [[ "${FAKE_SCENARIO:-drift}" == "mismatch" && "$call" == "1" ]]; then
    case_name=wrong-case
fi

if [[ "$kind" == "execution" ]]; then
    printf 'execution\t%s\truntime_ms\t%s\n' "$case_name" "$value" >>"$output"
else
    phase="$(awk -v value="$value" 'BEGIN { if (value ~ /^[0-9.]+$/) printf "%.6f", value / 2; else print value }')"
    printf 'compile\t%s\tParse\t%s\n' "$case_name" "$phase" >>"$output"
    printf 'compile\t%s\tTOTAL\t%s\n' "$case_name" "$value" >>"$output"
fi

if [[ "${FAKE_SCENARIO:-drift}" == "duplicate" && "$call" == "1" ]]; then
    duplicate_line="$(tail -n 1 "$output")"
    printf '%s\n' "$duplicate_line" >>"$output"
fi
EOF
chmod +x "$FAKE_GATE"

run_gate() {
    local scenario="$1"
    local output_dir="$2"
    : >"$SEQUENCE_LOG"
    REAL_GATE="$REAL_GATE" \
    SEQUENCE_LOG="$SEQUENCE_LOG" \
    FAKE_SCENARIO="$scenario" \
    PAIRED_BENCHMARK_GATE_SCRIPT="$FAKE_GATE" \
        bash "$PAIRED_GATE" \
            --base-kswiftc "$BASE_COMPILER" \
            --candidate-kswiftc "$CANDIDATE_COMPILER" \
            --baseline "$BASELINE" \
            --output-dir "$output_dir" \
            --tolerance 10
}

expect_pass() {
    local scenario="$1"
    local output_dir="$TEMP_DIR/$scenario"
    if ! run_gate "$scenario" "$output_dir" >"$TEMP_DIR/$scenario.log" 2>&1; then
        cat "$TEMP_DIR/$scenario.log" >&2
        echo "FAIL: paired benchmark scenario should pass: $scenario" >&2
        exit 1
    fi
}

expect_fail() {
    local scenario="$1"
    local output_dir="$TEMP_DIR/$scenario"
    if run_gate "$scenario" "$output_dir" >"$TEMP_DIR/$scenario.log" 2>&1; then
        echo "FAIL: paired benchmark scenario should fail: $scenario" >&2
        exit 1
    fi
}

expect_pass drift

expected_sequence="$TEMP_DIR/expected-sequence.log"
: >"$expected_sequence"
while IFS=$'\t' read -r kind case_name _metric _value; do
    [[ "$kind" == "kind" ]] && continue
    key="$kind/$case_name"
    for compiler in base-kswiftc candidate-kswiftc candidate-kswiftc base-kswiftc \
                    candidate-kswiftc base-kswiftc base-kswiftc candidate-kswiftc \
                    base-kswiftc candidate-kswiftc candidate-kswiftc base-kswiftc; do
        printf '%s\t%s\n' "$key" "$compiler" >>"$expected_sequence"
    done
done <"$BASELINE"
cmp "$expected_sequence" "$SEQUENCE_LOG"
[[ "$(awk 'END { print NR - 1 }' "$TEMP_DIR/drift/paired-baseline.tsv")" == "9" ]]
[[ "$(awk 'END { print NR - 1 }' "$TEMP_DIR/drift/paired-candidate.tsv")" == "9" ]]
[[ "$(awk 'END { print NR - 1 }' "$TEMP_DIR/drift/pair-ratios.tsv")" == "9" ]]
[[ "$(awk 'END { print NR - 1 }' "$TEMP_DIR/drift/raw-samples.tsv")" == "108" ]]
grep -q 'Result: PASS (9 enforced measurements' "$TEMP_DIR/drift/summary.md"

expect_fail regression
grep -q 'Result: FAIL (9 of 9 enforced measurements' "$TEMP_DIR/regression/summary.md"

expect_fail any-pass
grep -q 'Result: FAIL (9 of 9 enforced measurements' "$TEMP_DIR/any-pass/summary.md"

expect_pass outlier
grep -q 'Result: PASS' "$TEMP_DIR/outlier/summary.md"

expect_pass boundary
grep -q $'\t10.000\tPASS$' "$TEMP_DIR/boundary/benchmark-report.tsv"

expect_fail over-boundary
grep -q $'\t10.010\tFAIL$' "$TEMP_DIR/over-boundary/benchmark-report.tsv"

for anomaly in missing duplicate nonnumeric mismatch; do
    expect_fail "$anomaly"
    grep -Eq 'error: (expected exactly one|malformed or mismatched)' "$TEMP_DIR/$anomaly.log"
done

DUPLICATE_BASELINE="$TEMP_DIR/duplicate-baseline.tsv"
cp "$BASELINE" "$DUPLICATE_BASELINE"
sed -n '2p' "$BASELINE" >>"$DUPLICATE_BASELINE"
if REAL_GATE="$REAL_GATE" SEQUENCE_LOG="$SEQUENCE_LOG" PAIRED_BENCHMARK_GATE_SCRIPT="$FAKE_GATE" \
    bash "$PAIRED_GATE" --base-kswiftc "$BASE_COMPILER" --candidate-kswiftc "$CANDIDATE_COMPILER" \
        --baseline "$DUPLICATE_BASELINE" --output-dir "$TEMP_DIR/duplicate-baseline-output" \
        >"$TEMP_DIR/duplicate-baseline.log" 2>&1; then
    echo 'FAIL: paired benchmark gate accepted a duplicate enforced baseline key' >&2
    exit 1
fi
grep -q 'error: duplicate enforced baseline metric' "$TEMP_DIR/duplicate-baseline.log"

INVALID_BASELINE="$TEMP_DIR/invalid-baseline.tsv"
sed '2s/100/not-a-number/' "$BASELINE" >"$INVALID_BASELINE"
if REAL_GATE="$REAL_GATE" SEQUENCE_LOG="$SEQUENCE_LOG" PAIRED_BENCHMARK_GATE_SCRIPT="$FAKE_GATE" \
    bash "$PAIRED_GATE" --base-kswiftc "$BASE_COMPILER" --candidate-kswiftc "$CANDIDATE_COMPILER" \
        --baseline "$INVALID_BASELINE" --output-dir "$TEMP_DIR/invalid-baseline-output" \
        >"$TEMP_DIR/invalid-baseline.log" 2>&1; then
    echo 'FAIL: paired benchmark gate accepted a nonnumeric enforced baseline value' >&2
    exit 1
fi
grep -q 'error: invalid enforced baseline row' "$TEMP_DIR/invalid-baseline.log"

MISSING_BASELINE="$TEMP_DIR/missing-baseline.tsv"
sed '2d' "$BASELINE" >"$MISSING_BASELINE"
if REAL_GATE="$REAL_GATE" SEQUENCE_LOG="$SEQUENCE_LOG" PAIRED_BENCHMARK_GATE_SCRIPT="$FAKE_GATE" \
    bash "$PAIRED_GATE" --base-kswiftc "$BASE_COMPILER" --candidate-kswiftc "$CANDIDATE_COMPILER" \
        --baseline "$MISSING_BASELINE" --output-dir "$TEMP_DIR/missing-baseline-output" \
        >"$TEMP_DIR/missing-baseline.log" 2>&1; then
    echo 'FAIL: paired benchmark gate accepted an 8-key enforced baseline' >&2
    exit 1
fi
grep -q 'error: enforced baseline is missing required metric: execution/arch010_hash_collections/runtime_ms' "$TEMP_DIR/missing-baseline.log"
grep -q 'error: enforced baseline must contain exactly 9 metrics, got 8' "$TEMP_DIR/missing-baseline.log"

UNKNOWN_BASELINE="$TEMP_DIR/unknown-baseline.tsv"
sed '2s/arch010_hash_collections/unknown_case/' "$BASELINE" >"$UNKNOWN_BASELINE"
if REAL_GATE="$REAL_GATE" SEQUENCE_LOG="$SEQUENCE_LOG" PAIRED_BENCHMARK_GATE_SCRIPT="$FAKE_GATE" \
    bash "$PAIRED_GATE" --base-kswiftc "$BASE_COMPILER" --candidate-kswiftc "$CANDIDATE_COMPILER" \
        --baseline "$UNKNOWN_BASELINE" --output-dir "$TEMP_DIR/unknown-baseline-output" \
        >"$TEMP_DIR/unknown-baseline.log" 2>&1; then
    echo 'FAIL: paired benchmark gate accepted an unknown replacement metric' >&2
    exit 1
fi
grep -q 'error: unexpected enforced baseline metric: execution/unknown_case/runtime_ms' "$TEMP_DIR/unknown-baseline.log"
grep -q 'error: enforced baseline is missing required metric: execution/arch010_hash_collections/runtime_ms' "$TEMP_DIR/unknown-baseline.log"

echo 'OK: paired benchmark gate balances drift, rejects persistent regressions, suppresses one-block outliers, and fails closed'
