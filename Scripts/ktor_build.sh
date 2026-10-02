#!/usr/bin/env bash
set -euo pipefail

# Compiles pinned snapshots of Ktor's core modules (and their kotlinx-io
# dependency) with kswiftc to track how close this compiler is to building
# real-world Kotlin Multiplatform code. Fetches sources into a cache dir
# outside the repo (git is not vendored), compiles each module with
# `--emit library`, and writes a TSV of diagnostic-code counts per module.
#
# This is a diagnostic probe, not a golden/regression test: it does not run
# kotlinc, is not wired into CI, and a module failing to compile is expected
# (see docs/ktor-build-status.md for the current gap inventory). Re-run this
# after compiler changes to see whether the gap inventory shrank.
#
# Usage:
#   bash Scripts/ktor_build.sh                  # fetch + compile all modules
#   bash Scripts/ktor_build.sh --no-fetch        # reuse an existing cache
#   bash Scripts/ktor_build.sh --module ktor_io  # compile a single module

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
# Space-separated flags appended to each kswiftc invocation, e.g.
# KSWIFTC_FLAGS="--stdlib-library /path/to/KSwiftKStdlib.kklib" to bypass the
# shared machine-wide stdlib cache under ~/Library/Caches/kswiftk/stdlib/,
# which can be stale or mid-write from another concurrent session.
KSWIFTC_FLAGS="${KSWIFTC_FLAGS:-}"
KSWIFTC_EXTRA_ARGS=()
if [[ -n "$KSWIFTC_FLAGS" ]]; then
  read -r -a KSWIFTC_EXTRA_ARGS <<< "$KSWIFTC_FLAGS"
fi
CACHE_DIR="${KTOR_BUILD_CACHE_DIR:-$ROOT_DIR/.ktor-build-cache}"
OUT_DIR="${KTOR_BUILD_OUT_DIR:-$ROOT_DIR/.ktor-build-out}"
KTOR_TAG="${KTOR_TAG:-3.6.0}"
KOTLINX_IO_TAG="${KOTLINX_IO_TAG:-0.9.1}"
DO_FETCH=1
ONLY_MODULE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-fetch) DO_FETCH=0; shift ;;
    --module) ONLY_MODULE="$2"; shift 2 ;;
    -h|--help)
      cat <<USAGE
Usage: $(basename "$0") [--no-fetch] [--module <name>]

Options:
  --no-fetch          Reuse the existing $CACHE_DIR checkout instead of cloning.
  --module <name>     Compile only this module (kotlinx_io|ktor_io|ktor_utils|ktor_http).
  -h, --help          Show this help.

Environment overrides: KSWIFTC, KTOR_BUILD_CACHE_DIR, KTOR_BUILD_OUT_DIR,
KTOR_TAG, KOTLINX_IO_TAG.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -x "$KSWIFTC" ]]; then
  echo "kswiftc not found at $KSWIFTC. Run 'swift build' first." >&2
  exit 1
fi

mkdir -p "$CACHE_DIR" "$OUT_DIR"

clone_sparse() {
  local url="$1" tag="$2" dest="$3" paths="$4"
  if [[ -d "$dest/.git" ]]; then
    return 0
  fi
  git clone --depth 1 --filter=blob:none --sparse -b "$tag" "$url" "$dest"
  ( cd "$dest" && git sparse-checkout set $paths )
}

if [[ "$DO_FETCH" -eq 1 ]]; then
  clone_sparse https://github.com/Kotlin/kotlinx-io "$KOTLINX_IO_TAG" \
    "$CACHE_DIR/kotlinx-io" "core bytestring"
  clone_sparse https://github.com/ktorio/ktor "$KTOR_TAG" \
    "$CACHE_DIR/ktor" "ktor-io ktor-utils ktor-http"
fi

# Module name -> source roots (space-separated, relative to $CACHE_DIR).
module_sources() {
  case "$1" in
    kotlinx_io) echo "kotlinx-io/core/common/src kotlinx-io/bytestring/common/src" ;;
    ktor_io) echo "ktor/ktor-io/common/src" ;;
    ktor_utils) echo "ktor/ktor-utils/common/src" ;;
    ktor_http) echo "ktor/ktor-http/common/src" ;;
    *) echo "" ;;
  esac
}

# Compile in dependency order unless a single module was requested.
MODULES="kotlinx_io ktor_io ktor_utils ktor_http"
if [[ -n "$ONLY_MODULE" ]]; then
  MODULES="$ONLY_MODULE"
fi

TSV="$OUT_DIR/summary.tsv"
echo -e "module\texit_code\tfile_count\terror_count\twarning_count\ttop_codes" > "$TSV"

for module in $MODULES; do
  roots="$(module_sources "$module")"
  if [[ -z "$roots" ]]; then
    echo "Unknown module: $module" >&2
    exit 1
  fi
  files=()
  for root in $roots; do
    while IFS= read -r f; do files+=("$f"); done < <(find "$CACHE_DIR/$root" -name '*.kt' | sort)
  done
  log="$OUT_DIR/$module.log"
  kklib="$OUT_DIR/$module.kklib"
  rm -rf "$kklib"
  set +e
  "$KSWIFTC" --emit library -m "$module" -o "$kklib" "${KSWIFTC_EXTRA_ARGS[@]}" "${files[@]}" > "$log" 2>&1
  exit_code=$?
  set -e
  error_count=$(grep -c 'error KSWIFTK' "$log" || true)
  warning_count=$(grep -c 'warning KSWIFTK' "$log" || true)
  top_codes=$(grep -o 'KSWIFTK-[A-Z]*-[0-9A-Z]*' "$log" | sort | uniq -c | sort -rn | head -5 \
    | awk '{printf "%s:%s;", $2, $1}')
  echo -e "$module\t$exit_code\t${#files[@]}\t$error_count\t$warning_count\t$top_codes" >> "$TSV"
  echo "== $module: exit=$exit_code files=${#files[@]} errors=$error_count warnings=$warning_count =="
done

echo
echo "Summary written to $TSV"
column -t -s $'\t' "$TSV"
