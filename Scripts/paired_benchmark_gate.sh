#!/usr/bin/env bash
# Compare base and candidate compilers with per-metric crossover measurements.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

BASE_KSWIFTC="${BASE_KSWIFTC:-}"
CANDIDATE_KSWIFTC="${KSWIFTC:-${KSWIFTKC:-}}"
BASELINE="${BENCHMARK_BASELINE:-$SCRIPT_DIR/benchmark_baseline.tsv}"
OUTPUT_DIR="${BENCHMARK_OUTPUT_DIR:-}"
TOLERANCE="${BENCHMARK_TOLERANCE_PERCENT:-10}"
BENCHMARK_GATE_SCRIPT="${PAIRED_BENCHMARK_GATE_SCRIPT:-$SCRIPT_DIR/benchmark_gate.sh}"

usage() {
    cat >&2 <<'EOF'
Usage:
  paired_benchmark_gate.sh --base-kswiftc PATH --candidate-kswiftc PATH
                           --baseline PATH --output-dir PATH
                           [--tolerance PERCENT]

For every enforced metric, measures three crossover blocks in ABBA, BAAB,
ABBA order. Each compiler receives six samples. The gate takes the median of
the three adjacent AB ratios and the median of the three adjacent BA ratios,
then gates their geometric mean once.
EOF
}

while (($# > 0)); do
    case "$1" in
        --base-kswiftc)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            BASE_KSWIFTC="$2"
            shift 2
            ;;
        --candidate-kswiftc)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            CANDIDATE_KSWIFTC="$2"
            shift 2
            ;;
        --baseline)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            BASELINE="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --tolerance)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            TOLERANCE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

[[ -x "$BASE_KSWIFTC" ]] || {
    echo "error: base kswiftc not found or not executable: $BASE_KSWIFTC" >&2
    exit 1
}
[[ -x "$CANDIDATE_KSWIFTC" ]] || {
    echo "error: candidate kswiftc not found or not executable: $CANDIDATE_KSWIFTC" >&2
    exit 1
}
[[ -f "$BASELINE" ]] || {
    echo "error: benchmark baseline TSV not found: $BASELINE" >&2
    exit 1
}
[[ -f "$BENCHMARK_GATE_SCRIPT" ]] || {
    echo "error: benchmark gate script not found: $BENCHMARK_GATE_SCRIPT" >&2
    exit 1
}
[[ -n "$OUTPUT_DIR" ]] || {
    echo "error: --output-dir is required" >&2
    exit 2
}
if [[ ! "$TOLERANCE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "error: tolerance must be a non-negative number: $TOLERANCE" >&2
    exit 2
fi

mkdir -p "$OUTPUT_DIR/raw"

metrics="$OUTPUT_DIR/enforced-metrics.tsv"
if ! awk -F '\t' '
    BEGIN {
        OFS = "\t"
        expected["execution" SUBSEP "arch010_hash_collections" SUBSEP "runtime_ms"] = "execution/arch010_hash_collections/runtime_ms"
        expected["execution" SUBSEP "compile_medium" SUBSEP "runtime_ms"] = "execution/compile_medium/runtime_ms"
        expected["execution" SUBSEP "filter" SUBSEP "runtime_ms"] = "execution/filter/runtime_ms"
        expected["execution" SUBSEP "for_in_range" SUBSEP "runtime_ms"] = "execution/for_in_range/runtime_ms"
        expected["execution" SUBSEP "map" SUBSEP "runtime_ms"] = "execution/map/runtime_ms"
        expected["execution" SUBSEP "sort" SUBSEP "runtime_ms"] = "execution/sort/runtime_ms"
        expected["compile" SUBSEP "hello" SUBSEP "TOTAL"] = "compile/hello/TOTAL"
        expected["compile" SUBSEP "medium" SUBSEP "TOTAL"] = "compile/medium/TOTAL"
        expected["compile" SUBSEP "stdlib-only" SUBSEP "TOTAL"] = "compile/stdlib-only/TOTAL"
        print "kind", "case", "metric", "value_ms"
    }
    $1 == "kind" || $1 ~ /^#/ || $1 == "" { next }
    {
        if (NF != 4 || ($1 != "execution" && $1 != "compile") || $2 == "" || $3 == "" || $4 !~ /^[0-9]+([.][0-9]+)?$/ || $4 == 0) {
            printf "error: invalid enforced baseline row: %s\n", $0 > "/dev/stderr"
            invalid = 1
            next
        }
        key = $1 SUBSEP $2 SUBSEP $3
        if (key in seen) {
            printf "error: duplicate enforced baseline metric: %s/%s/%s\n", $1, $2, $3 > "/dev/stderr"
            invalid = 1
            next
        }
        if (!(key in expected)) {
            printf "error: unexpected enforced baseline metric: %s/%s/%s\n", $1, $2, $3 > "/dev/stderr"
            invalid = 1
            next
        }
        seen[key] = 1
        print
        count++
    }
    END {
        for (key in expected) {
            if (!(key in seen)) {
                printf "error: enforced baseline is missing required metric: %s\n", expected[key] > "/dev/stderr"
                invalid = 1
            }
        }
        if (count != 9) {
            printf "error: enforced baseline must contain exactly 9 metrics, got %d\n", count > "/dev/stderr"
            invalid = 1
        }
        if (invalid) exit 1
    }
' "$BASELINE" >"$metrics"; then
    exit 1
fi

paired_baseline="$OUTPUT_DIR/paired-baseline.tsv"
paired_candidate="$OUTPUT_DIR/paired-candidate.tsv"
ratios="$OUTPUT_DIR/pair-ratios.tsv"
samples="$OUTPUT_DIR/raw-samples.tsv"
report="$OUTPUT_DIR/benchmark-report.tsv"
comparison_summary="$OUTPUT_DIR/comparison-summary.md"
summary="$OUTPUT_DIR/summary.md"

printf 'kind\tcase\tmetric\tvalue_ms\n' >"$paired_baseline"
printf 'kind\tcase\tmetric\tvalue_ms\n' >"$paired_candidate"
printf 'kind\tcase\tmetric\tbase_median_ms\tcandidate_median_ms\tab_pair_1_ratio\tab_pair_2_ratio\tab_pair_3_ratio\tba_pair_1_ratio\tba_pair_2_ratio\tba_pair_3_ratio\tab_median_ratio\tba_median_ratio\tbalanced_ratio\tnormalized_candidate_ms\n' >"$ratios"
printf 'kind\tcase\tmetric\tblock\tposition\tcompiler\tvalue_ms\traw_tsv\n' >"$samples"

median_values() {
    printf '%s\n' "$@" | sort -n | awk '
        { values[NR] = $1 }
        END {
            if (NR == 0) exit 1
            if (NR % 2) printf "%.6f\n", values[(NR + 1) / 2]
            else printf "%.6f\n", (values[NR / 2] + values[NR / 2 + 1]) / 2
        }'
}

extract_sample() {
    local path="$1"
    local expected_kind="$2"
    local expected_case="$3"
    local expected_metric="$4"

    awk -F '\t' -v kind="$expected_kind" -v case_name="$expected_case" -v metric="$expected_metric" '
        FNR == 1 {
            if ($0 != "kind\tcase\tmetric\tvalue_ms") {
                printf "error: invalid benchmark TSV header in %s\n", FILENAME > "/dev/stderr"
                invalid = 1
            }
            next
        }
        {
            if (NF != 4 || $1 != kind || $2 != case_name || $3 == "" || $4 !~ /^[0-9]+([.][0-9]+)?$/ || $4 == 0) {
                printf "error: malformed or mismatched benchmark sample in %s: %s\n", FILENAME, $0 > "/dev/stderr"
                invalid = 1
                next
            }
            if ($3 == metric) {
                count++
                value = $4
            }
        }
        END {
            if (count != 1) {
                printf "error: expected exactly one %s/%s/%s sample in %s, got %d\n", kind, case_name, metric, FILENAME, count > "/dev/stderr"
                invalid = 1
            }
            if (invalid) exit 1
            print value
        }
    ' "$path"
}

measure_sample() {
    local kind="$1"
    local case_name="$2"
    local metric="$3"
    local metric_index="$4"
    local block="$5"
    local position="$6"
    local compiler_label="$7"
    local compiler="$8"
    local path="$OUTPUT_DIR/raw/metric-${metric_index}-block-${block}-position-${position}-${compiler_label}.tsv"

    echo "Measuring $kind/$case_name/$metric block $block position $position ($compiler_label)"
    KSWIFTC="$compiler" bash "$BENCHMARK_GATE_SCRIPT" \
        --measure-only \
        --measure-case "$kind/$case_name" \
        --baseline "$BASELINE" \
        --output "$path" \
        --execution-runs 1 \
        --compile-runs 1

    MEASURED_VALUE="$(extract_sample "$path" "$kind" "$case_name" "$metric")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$kind" "$case_name" "$metric" "$block" "$position" "$compiler_label" "$MEASURED_VALUE" "${path#"$OUTPUT_DIR/"}" >>"$samples"
}

metric_index=0
while IFS=$'\t' read -r kind case_name metric _reference_value; do
    [[ "$kind" == "kind" ]] && continue
    metric_index=$((metric_index + 1))
    base_values=()
    candidate_values=()
    ab_ratios=()
    ba_ratios=()

    for block in 1 2 3; do
        if ((block % 2 == 1)); then
            order=(base candidate candidate base)
        else
            order=(candidate base base candidate)
        fi
        block_labels=()
        block_values=()

        for position in 1 2 3 4; do
            compiler_label="${order[$((position - 1))]}"
            if [[ "$compiler_label" == "base" ]]; then
                compiler="$BASE_KSWIFTC"
            else
                compiler="$CANDIDATE_KSWIFTC"
            fi
            measure_sample "$kind" "$case_name" "$metric" "$metric_index" "$block" "$position" "$compiler_label" "$compiler"
            block_labels+=("$compiler_label")
            block_values+=("$MEASURED_VALUE")
            if [[ "$compiler_label" == "base" ]]; then
                base_values+=("$MEASURED_VALUE")
            else
                candidate_values+=("$MEASURED_VALUE")
            fi
        done

        if ((${#block_labels[@]} != 4 || ${#block_values[@]} != 4)); then
            echo "error: crossover block $block did not produce four ordered samples for $kind/$case_name/$metric" >&2
            exit 1
        fi

        for pair_start in 0 2; do
            first_label="${block_labels[$pair_start]}"
            first_value="${block_values[$pair_start]}"
            second_label="${block_labels[$((pair_start + 1))]}"
            second_value="${block_values[$((pair_start + 1))]}"
            if [[ "$first_label" == "base" && "$second_label" == "candidate" ]]; then
                ab_ratios+=("$(awk -v base="$first_value" -v candidate="$second_value" 'BEGIN { printf "%.9f\n", candidate / base }')")
            elif [[ "$first_label" == "candidate" && "$second_label" == "base" ]]; then
                ba_ratios+=("$(awk -v candidate="$first_value" -v base="$second_value" 'BEGIN { printf "%.9f\n", candidate / base }')")
            else
                echo "error: crossover block $block contains a non-paired order at positions $((pair_start + 1))-$((pair_start + 2))" >&2
                exit 1
            fi
        done
    done

    if ((${#base_values[@]} != 6 || ${#candidate_values[@]} != 6 || ${#ab_ratios[@]} != 3 || ${#ba_ratios[@]} != 3)); then
        echo "error: incomplete crossover samples for $kind/$case_name/$metric" >&2
        exit 1
    fi

    base_median="$(median_values "${base_values[@]}")"
    candidate_median="$(median_values "${candidate_values[@]}")"
    ab_median="$(median_values "${ab_ratios[@]}")"
    ba_median="$(median_values "${ba_ratios[@]}")"
    balanced_ratio="$(awk -v ab="$ab_median" -v ba="$ba_median" 'BEGIN { printf "%.9f\n", sqrt(ab * ba) }')"
    normalized_candidate="$(awk -v baseline="$base_median" -v ratio="$balanced_ratio" 'BEGIN { printf "%.6f\n", baseline * ratio }')"

    printf '%s\t%s\t%s\t%s\n' "$kind" "$case_name" "$metric" "$base_median" >>"$paired_baseline"
    printf '%s\t%s\t%s\t%s\n' "$kind" "$case_name" "$metric" "$normalized_candidate" >>"$paired_candidate"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$kind" "$case_name" "$metric" "$base_median" "$candidate_median" \
        "${ab_ratios[0]}" "${ab_ratios[1]}" "${ab_ratios[2]}" \
        "${ba_ratios[0]}" "${ba_ratios[1]}" "${ba_ratios[2]}" \
        "$ab_median" "$ba_median" "$balanced_ratio" "$normalized_candidate" >>"$ratios"
done <"$metrics"

expected_metrics="$(awk 'END { print NR - 1 }' "$metrics")"
for generated in "$paired_baseline" "$paired_candidate" "$ratios"; do
    actual_metrics="$(awk 'END { print NR - 1 }' "$generated")"
    if [[ "$actual_metrics" != "$expected_metrics" ]]; then
        echo "error: output metric count mismatch in $generated: expected $expected_metrics, got $actual_metrics" >&2
        exit 1
    fi
done

comparison_status=0
bash "$BENCHMARK_GATE_SCRIPT" \
    --compare-only \
    --baseline "$paired_baseline" \
    --measured "$paired_candidate" \
    --output "$report" \
    --summary "$comparison_summary" \
    --tolerance "$TOLERANCE" || comparison_status=$?

{
    echo '# Paired benchmark retry'
    echo
    echo 'Each enforced metric was measured in three crossover blocks: ABBA, BAAB, ABBA (A = base, B = candidate).'
    echo
    echo 'Each compiler has six raw samples per metric. The gate takes the median of the three adjacent AB ratios and the median of the three adjacent BA ratios, then uses their geometric mean.'
    echo
    echo 'The table compares the base median with that median multiplied by the order-balanced ratio; actual compiler medians and all adjacent-pair ratios are in pair-ratios.tsv.'
    echo
    cat "$comparison_summary"
} >"$summary"

exit "$comparison_status"
