#!/usr/bin/env bash
# Compare per-case kswiftc processes against one `kswiftc --batch` process.
# Usage: Scripts/kswiftc_batch_benchmark.sh [N] [case.kt ...]   (default: 8 x hello.kt, executables compared by run output)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KSWIFTC="${KSWIFTC:-$ROOT/.build/debug/kswiftc}"
N="${1:-8}"; shift || true
CASES=("$@"); [[ ${#CASES[@]} -eq 0 ]] && CASES=("$ROOT/Scripts/diff_cases/hello.kt")
WORK="$(mktemp -d -t kswiftk-batch-bench-XXXXXX)"; trap 'rm -rf "$WORK"' EXIT
manifest="$WORK/manifest.tsv"; : >"$manifest"
for ((i = 0; i < N; i++)); do
  kt="${CASES[$((i % ${#CASES[@]}))]}"
  printf '%s\t%s\t%s\t--no-incremental\t%s\t-o\t%s\n' "$WORK/b$i.out" "$WORK/b$i.err" "$WORK/b$i.exit" "$kt" "$WORK/b$i.bin" >>"$manifest"
done
s=$(date +%s); for ((i = 0; i < N; i++)); do
  kt="${CASES[$((i % ${#CASES[@]}))]}"
  "$KSWIFTC" --no-incremental "$kt" -o "$WORK/p$i.bin" >"$WORK/p$i.out" 2>"$WORK/p$i.err" || true
done; per=$(( $(date +%s) - s ))
s=$(date +%s); "$KSWIFTC" --batch "$manifest"; bat=$(( $(date +%s) - s ))
mismatch=0
for ((i = 0; i < N; i++)); do
  [[ "$("$WORK/p$i.bin" 2>&1)" == "$("$WORK/b$i.bin" 2>&1)" ]] || mismatch=$((mismatch + 1))
done
echo "cases=$N per-process=${per}s batch=${bat}s run-output-mismatches=$mismatch"
