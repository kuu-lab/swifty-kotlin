#!/usr/bin/env bash
# KSP-INF-007: Micro-benchmark harness for migration API runtime performance.
# Compiles each Kotlin source in Scripts/benchmark_cases/ with kswiftc and
# reports the median wall-clock execution time over multiple runs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RUNS="${BENCH_RUNS:-7}"
RELEASE="${BENCH_RELEASE:-0}"

if [[ "$RELEASE" == "1" ]]; then
    BUILD_CONFIG="release"
else
    BUILD_CONFIG="debug"
fi
KSWIFTC="${KSWIFTKC:-$ROOT_DIR/.build/$BUILD_CONFIG/kswiftc}"

if [[ ! -x "$KSWIFTC" ]]; then
    echo "kswiftc not found at $KSWIFTC; building $BUILD_CONFIG..." >&2
    if [[ "$RELEASE" == "1" ]]; then
        (cd "$ROOT_DIR" && swift build -c release)
    else
        (cd "$ROOT_DIR" && swift build)
    fi
fi

if [[ ! -x "$KSWIFTC" ]]; then
    echo "error: kswiftc still not found at $KSWIFTC" >&2
    exit 1
fi

CASES_DIR="$SCRIPT_DIR/benchmark_cases"
if [[ ! -d "$CASES_DIR" ]]; then
    echo "error: benchmark cases directory not found: $CASES_DIR" >&2
    exit 1
fi

# $EPOCHREALTIME (bash >= 5) is a pure variable expansion, unlike `date`,
# so it avoids forking a subprocess inside the timed hot loop below — that
# fork+exec latency would otherwise add noise to each measured sample.
if (( BASH_VERSINFO[0] >= 5 )); then
    now_ns() { printf -v "$1" '%s000' "${EPOCHREALTIME/./}"; }
else
    now_ns() { printf -v "$1" '%s' "$(date +%s%N)"; }
fi

echo "Benchmarking with $KSWIFTC ($BUILD_CONFIG), $RUNS runs per case..." >&2
echo ""
printf "%-20s %10s\n" "Case" "Median (ms)"
printf "%-20s %10s\n" "----" "-----------"

tmp_out=""
trap 'rm -f "$tmp_out"' EXIT
for kt in "$CASES_DIR"/*.kt; do
    name="$(basename "$kt" .kt)"
    tmp_out="$(mktemp "${TMPDIR:-/tmp}/kswiftk_bench_${name}.XXXXXX")"

    "$KSWIFTC" --emit executable -o "$tmp_out" "$kt" >/dev/null

    times=()
    for ((i = 1; i <= RUNS; i++)); do
        now_ns start_ns
        "$tmp_out" >/dev/null
        now_ns end_ns
        elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
        times+=("$elapsed_ms")
    done

    rm -f "$tmp_out"

    # Compute median
    median="$(printf '%s\n' "${times[@]}" | sort -n | awk '{ a[NR] = $1 } END { if (NR % 2) { print a[(NR + 1) / 2] } else { print (a[NR / 2] + a[NR / 2 + 1]) / 2 } }')"

    printf "%-20s %10s\n" "$name" "$median"
done
