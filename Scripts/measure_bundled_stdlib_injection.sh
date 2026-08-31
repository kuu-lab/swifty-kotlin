#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
KSWIFTC="$ROOT_DIR/.build/debug/kswiftc"
HELLO_KT="$ROOT_DIR/Scripts/diff_cases/hello.kt"

if [[ ! -x "$KSWIFTC" ]]; then
    echo "kswiftc not found: $KSWIFTC" >&2
    echo "Run 'swift build' first." >&2
    exit 1
fi

if [[ ! -f "$HELLO_KT" ]]; then
    echo "hello.kt not found: $HELLO_KT" >&2
    exit 1
fi

# Baseline median (36.05ms) + 100ms, per "Bundled Stdlib Injection Cost" in docs/refactoring-metrics.md.
CACHE_TRIGGER_MS=136.05

RUNS="${1:-5}"
TMPDIR="${TMPDIR:-/tmp}"
OUT_DIR="$(mktemp -d "$TMPDIR/kswiftk-bundled-injection.XXXXXX")"
ARTIFACT_DIR="$OUT_DIR/KSwiftKStdlib.kklib"
trap 'rm -rf "$OUT_DIR"' EXIT

extract_subphase() {
    local phase="$1"
    local file="$2"
    awk -v p="$phase" '
        $0 ~ "^" p "[[:space:]]" { want=1; next }
        want && /^  bundled-stdlib[[:space:]]/ { print $2; want=0; exit }
    ' "$file"
}

measure_artifact_build() {
    local artifact_dir="$1"
    local stderr_file="$2"
    time_command "%.2f" "$stderr_file" \
        "$KSWIFTC" --stdlib-only --emit library -o "$artifact_dir"
}

measure_shared_candidate_compile() {
    local artifact_dir="$1"
    local output="$2"
    local stderr_file="$3"
    time_command "%.2f" "$stderr_file" \
        "$KSWIFTC" --no-stdlib --stdlib-library "$artifact_dir" "$HELLO_KT" -o "$output"
}

lex_values=()
parse_values=()
for ((run = 1; run <= RUNS; run++)); do
    stderr_file="$OUT_DIR/run$run.txt"
    "$KSWIFTC" --emit kir "$HELLO_KT" -o "$OUT_DIR/out$run" -Xfrontend time-phases 2>"$stderr_file" || true
    lex_ms="$(extract_subphase "Lex" "$stderr_file")"
    parse_ms="$(extract_subphase "Parse" "$stderr_file")"
    if [[ -z "$lex_ms" || -z "$parse_ms" ]]; then
        echo "Failed to extract bundled-stdlib timing from run $run" >&2
        cat "$stderr_file" >&2
        exit 1
    fi
    lex_values+=("$lex_ms")
    parse_values+=("$parse_ms")
    printf 'run %d: Lex bundled-stdlib = %s ms, Parse bundled-stdlib = %s ms\n' "$run" "$lex_ms" "$parse_ms"
done

lex_median="$(median "%.2f" "${lex_values[@]}")"
parse_median="$(median "%.2f" "${parse_values[@]}")"
total_median="$(awk -v a="$lex_median" -v b="$parse_median" 'BEGIN { printf "%.2f", a + b }')"

printf '\nMedian bundled stdlib injection cost over %d runs:\n' "$RUNS"
printf '  Lex bundled-stdlib:  %s ms\n' "$lex_median"
printf '  Parse bundled-stdlib: %s ms\n' "$parse_median"
printf '  Total:               %s ms\n' "$total_median"

if (( $(awk -v t="$total_median" -v trig="$CACHE_TRIGGER_MS" 'BEGIN { print (t >= trig) ? 1 : 0 }') )); then
    printf 'Trigger (>= %s ms): CACHED\n' "$CACHE_TRIGGER_MS" >&2
else
    printf 'Trigger (>= %s ms): not reached\n' "$CACHE_TRIGGER_MS" >&2
fi

printf '\nShared stdlib artifact measurement:\n'
artifact_build_ms="$(measure_artifact_build "$ARTIFACT_DIR" "$OUT_DIR/artifact_build.stderr")"
printf '  Artifact build (stdlib-only .kklib): %s ms\n' "$artifact_build_ms"

shared_compile_ms="$(measure_shared_candidate_compile "$ARTIFACT_DIR" "$OUT_DIR/shared.out" "$OUT_DIR/shared.stderr")"
printf '  Shared candidate compile (hello.kt): %s ms\n' "$shared_compile_ms"
