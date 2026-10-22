#!/usr/bin/env bash
# Compare `kswiftc --run` (KIR interpreter, with native fallback) against the
# natively compiled executable for the same Kotlin file(s).
#
#   bash Scripts/diff_run_interpreter.sh Scripts/diff_cases/hello.kt [more.kt ...]
#
# For each case it reports whether the interpreter handled it or fell back
# (the fallback note is printed on stderr by kswiftc) and fails when stdout or
# the exit code differs from the native executable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <case.kt> [case.kt ...]" >&2
  exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

for case_file in "$@"; do
  name="$(basename "$case_file" .kt)"
  "$KSWIFTC" "$case_file" -o "$work/$name.native" >/dev/null 2>"$work/$name.native.err" || {
    echo "SKIP $name (native compile failed)"
    continue
  }
  set +e
  "$work/$name.native" >"$work/$name.native.out" 2>/dev/null
  native_status=$?
  "$KSWIFTC" --run "$case_file" >"$work/$name.run.out" 2>"$work/$name.run.err"
  run_status=$?
  set -e

  mode="interpreted"
  if grep -q "falling back to native execution" "$work/$name.run.err"; then
    mode="fallback ($(sed -n 's/.*execution (\(.*\))/\1/p' "$work/$name.run.err" | head -1))"
  fi
  if [[ "$native_status" -eq "$run_status" ]] && cmp -s "$work/$name.native.out" "$work/$name.run.out"; then
    echo "PASS $name [$mode]"
  else
    echo "FAIL $name [$mode] native_exit=$native_status run_exit=$run_status"
    diff "$work/$name.native.out" "$work/$name.run.out" | head -20 || true
    failures=$((failures + 1))
  fi
done

exit $((failures > 0 ? 1 : 0))
