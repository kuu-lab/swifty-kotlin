#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
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

RUNS="${1:-5}"
TMPDIR="${TMPDIR:-/tmp}"
OUT_DIR="$(mktemp -d "$TMPDIR/kswiftk-bundled-injection.XXXXXX")"
trap 'rm -rf "$OUT_DIR"' EXIT

extract_subphase() {
    local phase="$1"
    local file="$2"
    awk -v p="$phase" '
        $0 ~ "^" p "[[:space:]]" { want=1; next }
        want && /^  bundled-stdlib[[:space:]]/ { print $2; want=0; exit }
    ' "$file"
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

median() {
    local arr=("$@")
    local n=${#arr[@]}
    if (( n == 0 )); then
        echo 0
        return
    fi
    local sorted
    readarray -t sorted < <(printf '%s\n' "${arr[@]}" | sort -n)
    if (( n % 2 == 1 )); then
        echo "${sorted[$(( n / 2 ))]}"
    else
        local a="${sorted[$(( n / 2 - 1 ))]}"
        local b="${sorted[$(( n / 2 ))]}"
        awk -v a="$a" -v b="$b" 'BEGIN { printf "%.2f", (a + b) / 2 }'
    fi
}

lex_median="$(median "${lex_values[@]}")"
parse_median="$(median "${parse_values[@]}")"
total_median="$(awk -v a="$lex_median" -v b="$parse_median" 'BEGIN { printf "%.2f", a + b }')"

printf '\nMedian bundled stdlib injection cost over %d runs:\n' "$RUNS"
printf '  Lex bundled-stdlib:  %s ms\n' "$lex_median"
printf '  Parse bundled-stdlib: %s ms\n' "$parse_median"
printf '  Total:               %s ms\n' "$total_median"

if (( $(awk -v t="$total_median" 'BEGIN { print (t >= 137.29) ? 1 : 0 }') )); then
    printf 'Trigger (>= 137.29 ms): CACHED\n' >&2
else
    printf 'Trigger (>= 137.29 ms): not reached\n' >&2
fi
