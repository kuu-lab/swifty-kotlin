#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
KSWIFTK_STDLIB_LIBRARY="${KSWIFTK_STDLIB_LIBRARY:-}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") <case.kt> [support.kt ...]

Compile and run one candidate-only case, then compare stdout with the adjacent
<case>.expected file. Additional Kotlin sources are compiled into the same
module as the case.

Set KSWIFTC to use a different compiler binary.
Set KSWIFTK_STDLIB_LIBRARY to reuse a prebuilt KSwiftKStdlib.kklib.
USAGE
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

resolve_source_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$ROOT_DIR/$1" ;;
  esac
}

case_path="$(resolve_source_path "$1")"
shift
if [[ "$case_path" != *.kt || ! -f "$case_path" ]]; then
  echo "Kotlin case not found: $case_path" >&2
  exit 2
fi

expected_path="${case_path%.kt}.expected"
if [[ ! -f "$expected_path" ]]; then
  echo "Expected output file not found: $expected_path" >&2
  exit 2
fi

if [[ ! -x "$KSWIFTC" ]]; then
  echo "kswiftc not found or not executable: $KSWIFTC" >&2
  exit 2
fi

if [[ -z "$KSWIFTK_STDLIB_LIBRARY" && -d "$ROOT_DIR/.artifacts/diff_kotlinc/KSwiftKStdlib.kklib" ]]; then
  KSWIFTK_STDLIB_LIBRARY="$ROOT_DIR/.artifacts/diff_kotlinc/KSwiftKStdlib.kklib"
fi
if [[ -n "$KSWIFTK_STDLIB_LIBRARY" && ( ! -d "$KSWIFTK_STDLIB_LIBRARY" || ! -f "$KSWIFTK_STDLIB_LIBRARY/manifest.json" ) ]]; then
  echo "Stdlib library does not exist or is missing manifest.json: $KSWIFTK_STDLIB_LIBRARY" >&2
  exit 2
fi

stdlib_args=()
if [[ -n "$KSWIFTK_STDLIB_LIBRARY" ]]; then
  stdlib_args=(--stdlib-library "$KSWIFTK_STDLIB_LIBRARY")
fi

input_paths=("$case_path")
for support_path in "$@"; do
  support_path="$(resolve_source_path "$support_path")"
  if [[ "$support_path" != *.kt || ! -f "$support_path" ]]; then
    echo "Kotlin support source not found: $support_path" >&2
    exit 2
  fi
  input_paths+=("$support_path")
done

temp_dir="$(mktemp -d -t kswiftk-candidate-only.XXXXXX)"
trap 'rm -rf "$temp_dir"' EXIT

candidate_binary="$temp_dir/candidate.out"
candidate_stdout="$temp_dir/candidate.stdout"
candidate_stderr="$temp_dir/candidate.stderr"

"$KSWIFTC" "${stdlib_args[@]}" "${input_paths[@]}" -o "$candidate_binary"
candidate_run_exit=0
"$candidate_binary" >"$candidate_stdout" 2>"$candidate_stderr" || candidate_run_exit=$?
if [[ $candidate_run_exit -ne 0 ]]; then
  echo "Candidate exited with status $candidate_run_exit: $case_path" >&2
  if [[ -s "$candidate_stderr" ]]; then
    cat "$candidate_stderr" >&2
  fi
  exit "$candidate_run_exit"
fi

if ! diff -u "$expected_path" "$candidate_stdout"; then
  echo "FAIL candidate-only: $case_path" >&2
  exit 1
fi

echo "PASS candidate-only: $case_path"
