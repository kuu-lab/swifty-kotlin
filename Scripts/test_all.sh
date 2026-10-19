#!/usr/bin/env bash
# Run every Scripts/test_*.sh regression test (except this file) and summarize.
# A new test_*.sh is picked up automatically, so it cannot be left out of CI.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SELF="$(basename "${BASH_SOURCE[0]:-$0}")"

passed=0
failed=()
for test_script in "$SCRIPT_DIR"/test_*.sh; do
  name="$(basename "$test_script")"
  [[ "$name" != "$SELF" ]] || continue
  echo "=== $name"
  if bash "$test_script"; then
    passed=$((passed + 1))
  else
    failed+=("$name")
  fi
done

echo
echo "Summary: passed=$passed failed=${#failed[@]}"
if ((${#failed[@]} > 0)); then
  printf 'FAILED: %s\n' "${failed[@]}" >&2
  exit 1
fi
