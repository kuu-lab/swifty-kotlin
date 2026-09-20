#!/usr/bin/env bash
# KUU-516: CI gate for runtime and compiler-phase benchmarks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BASELINE="${BENCHMARK_BASELINE:-$SCRIPT_DIR/benchmark_baseline.tsv}"
OUTPUT=""
SUMMARY=""
MEASURED=""
MEASURE_CASE=""
TOLERANCE="${BENCHMARK_TOLERANCE_PERCENT:-10}"
EXECUTION_RUNS="${BENCH_EXECUTION_RUNS:-5}"
COMPILE_RUNS="${BENCH_COMPILE_RUNS:-3}"
MODE="run"

usage() {
    cat >&2 <<'EOF'
Usage:
  benchmark_gate.sh [--baseline PATH] [--output PATH] [--summary PATH]
                    [--tolerance PERCENT] [--execution-runs N] [--compile-runs N]
                    [--measure-only [--measure-case KIND/CASE]]
  benchmark_gate.sh --compare-only --baseline PATH --measured PATH
                    [--output PATH] [--summary PATH] [--tolerance PERCENT]
EOF
}

while (($# > 0)); do
    case "$1" in
        --baseline)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            BASELINE="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            OUTPUT="$2"
            shift 2
            ;;
        --summary)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            SUMMARY="$2"
            shift 2
            ;;
        --measured)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            MEASURED="$2"
            shift 2
            ;;
        --measure-case)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            MEASURE_CASE="$2"
            shift 2
            ;;
        --tolerance)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            TOLERANCE="$2"
            shift 2
            ;;
        --execution-runs)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            EXECUTION_RUNS="$2"
            shift 2
            ;;
        --compile-runs)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            COMPILE_RUNS="$2"
            shift 2
            ;;
        --compare-only)
            MODE="compare"
            shift
            ;;
        --measure-only)
            MODE="measure"
            shift
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

is_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

if [[ ! "$TOLERANCE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "error: tolerance must be a non-negative number: $TOLERANCE" >&2
    exit 2
fi

if [[ "$MODE" != "compare" ]]; then
    is_positive_integer "$EXECUTION_RUNS" || {
        echo "error: execution run count must be a positive integer: $EXECUTION_RUNS" >&2
        exit 2
    }
    is_positive_integer "$COMPILE_RUNS" || {
        echo "error: compile run count must be a positive integer: $COMPILE_RUNS" >&2
        exit 2
    }
fi

if [[ -n "$MEASURE_CASE" ]]; then
    if [[ "$MODE" != "measure" || ! "$MEASURE_CASE" =~ ^(execution|compile)/[^/]+$ ]]; then
        echo "error: --measure-case requires --measure-only and KIND/CASE" >&2
        exit 2
    fi
fi

if [[ "$MODE" == "compare" ]]; then
    [[ -n "$MEASURED" ]] || {
        echo "error: --compare-only requires --measured" >&2
        exit 2
    }
    [[ -f "$MEASURED" ]] || {
        echo "error: measured TSV not found: $MEASURED" >&2
        exit 1
    }
fi

[[ -f "$BASELINE" ]] || {
    echo "error: benchmark baseline TSV not found: $BASELINE" >&2
    exit 1
}

validate_production_baseline() {
    local baseline_path="$1"
    awk -F '\t' '
        BEGIN {
            expected["execution" SUBSEP "arch010_hash_collections" SUBSEP "runtime_ms"] = "execution/arch010_hash_collections/runtime_ms"
            expected["execution" SUBSEP "compile_medium" SUBSEP "runtime_ms"] = "execution/compile_medium/runtime_ms"
            expected["execution" SUBSEP "filter" SUBSEP "runtime_ms"] = "execution/filter/runtime_ms"
            expected["execution" SUBSEP "for_in_range" SUBSEP "runtime_ms"] = "execution/for_in_range/runtime_ms"
            expected["execution" SUBSEP "map" SUBSEP "runtime_ms"] = "execution/map/runtime_ms"
            expected["execution" SUBSEP "sort" SUBSEP "runtime_ms"] = "execution/sort/runtime_ms"
            expected["compile" SUBSEP "hello" SUBSEP "TOTAL"] = "compile/hello/TOTAL"
            expected["compile" SUBSEP "medium" SUBSEP "TOTAL"] = "compile/medium/TOTAL"
            expected["compile" SUBSEP "stdlib-only" SUBSEP "TOTAL"] = "compile/stdlib-only/TOTAL"
        }
        $1 == "kind" || $1 ~ /^#/ || $1 == "" { next }
        {
            key = $1 SUBSEP $2 SUBSEP $3
            if (!(key in expected)) {
                printf "error: unexpected production benchmark metric: %s/%s/%s\n", $1, $2, $3 > "/dev/stderr"
                invalid = 1
                next
            }
            if (key in seen) {
                printf "error: duplicate production benchmark metric: %s/%s/%s\n", $1, $2, $3 > "/dev/stderr"
                invalid = 1
                next
            }
            if (NF != 4 || $4 !~ /^[0-9]+([.][0-9]+)?$/ || $4 == 0) {
                printf "error: invalid production benchmark row: %s\n", $0 > "/dev/stderr"
                invalid = 1
                next
            }
            seen[key] = 1
            count++
        }
        END {
            for (key in expected) {
                if (!(key in seen)) {
                    printf "error: production benchmark baseline is missing required metric: %s\n", expected[key] > "/dev/stderr"
                    invalid = 1
                }
            }
            if (count != 9) {
                printf "error: production benchmark baseline must contain exactly 9 metrics, got %d\n", count > "/dev/stderr"
                invalid = 1
            }
            if (invalid) exit 1
        }
    ' "$baseline_path"
}

# The stored-baseline fast path is a fixed production gate. Validate its key
# contract before measuring so removing the same target from both the baseline
# and the harness cannot silently turn a nine-metric gate into an eight-metric
# PASS. compare-only remains generic for focused fixtures and diagnostics.
if [[ "$MODE" == "run" ]]; then
    validate_production_baseline "$BASELINE"
fi

if [[ "$MODE" == "compare" ]]; then
    WORK_DIR=""
else
    if [[ -z "${KSWIFTC:-}" ]]; then
        KSWIFTC="${KSWIFTKC:-$ROOT_DIR/.build/release/kswiftc}"
    fi
    if [[ ! -x "$KSWIFTC" ]]; then
        echo "error: kswiftc not found or not executable: $KSWIFTC" >&2
        echo "Build the compiler first or set KSWIFTC to the matching executable." >&2
        exit 1
    fi
    WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-benchmark-gate.XXXXXX")"
    trap 'rm -rf "$WORK_DIR"' EXIT
fi

extract_phase() {
    local phase="$1"
    local timing_file="$2"
    awk -v phase="$phase" '$1 == phase && $2 ~ /^[0-9]+([.][0-9]+)?$/ { print $2; exit }' "$timing_file"
}

median() {
    printf '%s\n' "$@" | sort -n | awk '
        { values[NR] = $1 }
        END {
            if (NR == 0) exit 1
            if (NR % 2) print values[(NR + 1) / 2]
            else printf "%.2f\n", (values[NR / 2] + values[NR / 2 + 1]) / 2
        }'
}

require_measurement() {
    local label="$1"
    local value="$2"
    local timing_file="$3"
    if [[ -z "$value" || ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "error: could not parse $label from $timing_file" >&2
        cat "$timing_file" >&2
        exit 1
    fi
}

measure_compile_case() {
    local case_name="$1"
    local source_path="$2"
    local case_dir="$WORK_DIR/$case_name"
    mkdir -p "$case_dir"

    for ((run = 1; run <= COMPILE_RUNS; run++)); do
        local output_path="$case_dir/output-$run"
        local stdout_path="$case_dir/stdout-$run"
        local stderr_path="$case_dir/stderr-$run"
        local -a compiler_args

        if [[ "$case_name" == "stdlib-only" ]]; then
            compiler_args=(
                --stdlib-only
                --emit library
                -Xfrontend time-phases
                -o "$output_path"
            )
        else
            compiler_args=(
                --stdlib-from-source
                --emit kir
                -Xfrontend time-phases
                "$source_path"
                -o "$output_path"
            )
        fi

        if ! "$KSWIFTC" "${compiler_args[@]}" >"$stdout_path" 2>"$stderr_path"; then
            echo "error: compiler failed for $case_name run $run" >&2
            cat "$stdout_path" >&2
            cat "$stderr_path" >&2
            exit 1
        fi

    done

    local -a phases=()
    while IFS= read -r phase; do
        phases+=("$phase")
    done < <(awk '
        $0 !~ /^[[:space:]]/ && $2 ~ /^[0-9]+([.][0-9]+)?$/ && !seen[$1]++ { print $1 }
        END { if (!("TOTAL" in seen)) print "TOTAL" }
    ' "$case_dir/stderr-1")
    for phase in "${phases[@]}"; do
        for ((run = 1; run <= COMPILE_RUNS; run++)); do
            value="$(extract_phase "$phase" "$case_dir/stderr-$run")"
            require_measurement "$case_name $phase (run $run)" "$value" "$case_dir/stderr-$run"
            printf '%s\t%s\t%s\t%s\n' "$case_name" "$phase" "$run" "$value" >>"$case_dir/raw.tsv"
        done
        values=()
        while IFS=$'\t' read -r candidate_case candidate_phase _candidate_run candidate_value; do
            [[ "$candidate_case" == "$case_name" && "$candidate_phase" == "$phase" ]] || continue
            values+=("$candidate_value")
        done <"$case_dir/raw.tsv"
        printf 'compile\t%s\t%s\t%s\n' "$case_name" "$phase" "$(median "${values[@]}")" >>"$WORK_DIR/measured.tsv"
    done
}

compare_tsv() {
    local baseline_path="$1"
    local measured_path="$2"
    local report_path="$3"
    local summary_path="$4"
    local failed=0
    local rows=0
    local unbaselined=0

    if ! awk -F '\t' '
        NR == FNR {
            if ($1 != "kind" && $1 !~ /^#/ && $1 != "") required[$1 SUBSEP $2 SUBSEP $3] = $1 "/" $2 "/" $3
            next
        }
        $1 != "kind" && $1 !~ /^#/ && $1 != "" { measured[$1 SUBSEP $2 SUBSEP $3] = 1 }
        END {
            for (key in required) {
                if (!(key in measured)) {
                    printf "error: measured TSV is missing gated metric %s\n", required[key] > "/dev/stderr"
                    missing = 1
                }
            }
            if (missing) exit 1
        }
    ' "$baseline_path" "$measured_path"; then
        return 1
    fi

    mkdir -p "$(dirname "$report_path")"
    printf 'kind\tcase\tmetric\tbaseline_ms\tmeasured_ms\tdelta_ms\tdelta_percent\tstatus\n' >"$report_path"

    while IFS=$'\t' read -r kind case_name metric measured_value; do
        [[ "$kind" == "kind" || -z "$kind" || "$kind" == \#* ]] && continue
        if [[ -z "$case_name" || -z "$metric" || -z "$measured_value" ]]; then
            echo "error: malformed measured TSV row" >&2
            return 1
        fi
        if [[ ! "$measured_value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            echo "error: measured value is not numeric for $kind/$case_name/$metric: $measured_value" >&2
            return 1
        fi

        baseline_value="$(awk -F '\t' -v kind="$kind" -v case_name="$case_name" -v metric="$metric" '
            $0 !~ /^#/ && $1 != "kind" && $1 == kind && $2 == case_name && $3 == metric { print $4; exit }
        ' "$baseline_path")"
        if [[ -z "$baseline_value" ]]; then
            if [[ "$kind" == "execution" || "$metric" == "TOTAL" ]]; then
                echo "error: missing baseline for gated metric $kind/$case_name/$metric" >&2
                return 1
            fi
            printf '%s\t%s\t%s\t\t%s\t\t\tUNBASELINED\n' \
                "$kind" "$case_name" "$metric" "$measured_value" >>"$report_path"
            rows=$((rows + 1))
            unbaselined=$((unbaselined + 1))
            continue
        fi
        if [[ ! "$baseline_value" =~ ^[0-9]+([.][0-9]+)?$ || "$baseline_value" == "0" ]]; then
            echo "error: invalid baseline for $kind/$case_name/$metric: $baseline_value" >&2
            return 1
        fi

        delta_ms="$(awk -v measured="$measured_value" -v baseline="$baseline_value" 'BEGIN { printf "%.2f", measured - baseline }')"
        delta_percent="$(awk -v measured="$measured_value" -v baseline="$baseline_value" 'BEGIN { printf "%.3f", (measured - baseline) * 100 / baseline }')"
        status="$(awk -v measured="$measured_value" -v baseline="$baseline_value" -v tolerance="$TOLERANCE" \
            'BEGIN { print (((measured - baseline) * 100 / baseline) <= tolerance) ? "PASS" : "FAIL" }')"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$kind" "$case_name" "$metric" "$baseline_value" "$measured_value" "$delta_ms" "$delta_percent" "$status" >>"$report_path"
        rows=$((rows + 1))
        if [[ "$status" == "FAIL" ]]; then
            failed=$((failed + 1))
        fi
    done <"$measured_path"

    if ((rows == 0)); then
        echo "error: measured TSV contains no data rows: $measured_path" >&2
        return 1
    fi

    if [[ -n "$summary_path" ]]; then
        mkdir -p "$(dirname "$summary_path")"
        {
            echo '# Benchmark gate'
            echo
            echo "Regression tolerance: +${TOLERANCE}%"
            echo
            echo '| Kind | Case | Metric | Baseline (ms) | Measured (ms) | Delta | Status |'
            echo '|---|---|---|---:|---:|---:|---|'
            tail -n +2 "$report_path" | while IFS=$'\t' read -r row_kind row_case row_metric row_baseline row_measured row_delta row_percent row_status; do
                if [[ "$row_status" == "UNBASELINED" ]]; then
                    echo "| $row_kind | $row_case | $row_metric | — | $row_measured | — | UNBASELINED |"
                else
                    echo "| $row_kind | $row_case | $row_metric | $row_baseline | $row_measured | ${row_delta} ms (${row_percent}%) | $row_status |"
                fi
            done
            echo
            if ((failed == 0)); then
                gated_rows=$((rows - unbaselined))
                echo "Result: PASS ($gated_rows enforced measurements within regression tolerance; $unbaselined diagnostic rows without a baseline)."
            else
                gated_rows=$((rows - unbaselined))
                echo "Result: FAIL ($failed of $gated_rows enforced measurements exceeded the regression tolerance; $unbaselined diagnostic rows without a baseline)."
            fi
        } >"$summary_path"
    fi

    if ((failed > 0)); then
        echo "Benchmark regression gate failed: $failed of $rows measurements exceeded +${TOLERANCE}% from baseline." >&2
        return 1
    fi
    echo "Benchmark regression gate passed: $rows measurements stayed within +${TOLERANCE}% of baseline."
}

if [[ "$MODE" == "compare" ]]; then
    report_path="${OUTPUT:-${MEASURED%.tsv}.report.tsv}"
    compare_tsv "$BASELINE" "$MEASURED" "$report_path" "$SUMMARY"
    exit $?
fi

measured_path="$WORK_DIR/measured.tsv"
printf 'kind\tcase\tmetric\tvalue_ms\n' >"$measured_path"

measure_kind="${MEASURE_CASE%%/*}"
measure_case="${MEASURE_CASE#*/}"

if [[ -z "$MEASURE_CASE" || "$measure_kind" == "execution" ]]; then
    if [[ -n "$MEASURE_CASE" && ! -f "$SCRIPT_DIR/benchmark_cases/$measure_case.kt" ]]; then
        echo "error: unknown execution benchmark case: $measure_case" >&2
        exit 2
    fi
    BENCH_RUNS="$EXECUTION_RUNS" \
    BENCH_RELEASE=1 \
    BENCH_CASE="${MEASURE_CASE:+$measure_case}" \
    BENCH_OUTPUT_TSV="$measured_path" \
    KSWIFTC="$KSWIFTC" \
        bash "$SCRIPT_DIR/benchmark_stdlib_hof.sh"
fi

if [[ -z "$MEASURE_CASE" || "$measure_kind" == "compile" ]]; then
    case "$measure_case" in
        "" )
            measure_compile_case hello "$ROOT_DIR/Scripts/diff_cases/hello.kt"
            measure_compile_case medium "$ROOT_DIR/Scripts/benchmark_cases/compile_medium.kt"
            measure_compile_case stdlib-only ""
            ;;
        hello)
            measure_compile_case hello "$ROOT_DIR/Scripts/diff_cases/hello.kt"
            ;;
        medium)
            measure_compile_case medium "$ROOT_DIR/Scripts/benchmark_cases/compile_medium.kt"
            ;;
        stdlib-only)
            measure_compile_case stdlib-only ""
            ;;
        *)
            echo "error: unknown compile benchmark case: $measure_case" >&2
            exit 2
            ;;
    esac
fi

if [[ "$MODE" == "measure" ]]; then
    [[ -n "$OUTPUT" ]] || {
        echo "error: --measure-only requires --output" >&2
        exit 2
    }
    mkdir -p "$(dirname "$OUTPUT")"
    cp "$measured_path" "$OUTPUT"
    echo "Benchmark measurements written to $OUTPUT"
    exit 0
fi

report_path="${OUTPUT:-$WORK_DIR/benchmark-report.tsv}"
compare_tsv "$BASELINE" "$measured_path" "$report_path" "$SUMMARY"
