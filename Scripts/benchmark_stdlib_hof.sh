#!/usr/bin/env bash
# KSP-INF-007: Micro-benchmark harness for migration API runtime performance.
# Compiles each Kotlin source in Scripts/benchmark_cases/ with kswiftc and
# reports the median wall-clock execution time over multiple runs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

run_quietly() { "$@" >/dev/null; }

RUNS="${BENCH_RUNS:-7}"
RELEASE="${BENCH_RELEASE:-0}"

if [[ "$RELEASE" == "1" ]]; then
    BUILD_CONFIG="release"
    KSWIFTC="${KSWIFTKC:-$ROOT_DIR/.build/release/kswiftc}"
else
    BUILD_CONFIG="debug"
    KSWIFTC="${KSWIFTKC:-$ROOT_DIR/.build/debug/kswiftc}"
fi

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

echo "Benchmarking with $KSWIFTC ($BUILD_CONFIG), $RUNS runs per case..." >&2
echo ""
printf "%-20s %10s\n" "Case" "Median (ms)"
printf "%-20s %10s\n" "----" "-----------"

for kt in "$CASES_DIR"/*.kt; do
    name="$(basename "$kt" .kt)"
    tmp_out="$(mktemp "${TMPDIR:-/tmp}/kswiftk_bench_${name}.XXXXXX")"
    trap 'rm -f "$tmp_out"' EXIT

    "$KSWIFTC" --emit executable -o "$tmp_out" "$kt" >/dev/null

    times=()
    for ((i = 1; i <= RUNS; i++)); do
        elapsed_ms="$(time_command "%d" "" run_quietly "$tmp_out")"
        times+=("$elapsed_ms")
    done

    rm -f "$tmp_out"
    trap - EXIT

    median_ms="$(median "" "${times[@]}")"

    printf "%-20s %10s\n" "$name" "$median_ms"
done
