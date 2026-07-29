#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage: check_todo_ids.sh [TODO-file]
       check_todo_ids.sh --self-test

Detect duplicate task IDs in TODO.md.

The check only considers task-definition lines of the form
`- [ ] ID:` or `- [x] ID:`, so cross-references in prose are ignored.
IDs may have any number of hyphen-separated uppercase segments before the
final numeric segment (e.g. `BUG-162`, `KSP-467`, `DEBT-DIFF-005`,
`KSWIFTK-SEMA-0001`).

--self-test runs a small fixture-based regression check of the detection
logic itself (no TODO.md required) and exits nonzero if it regresses.
USAGE
}

# Prints any duplicate task IDs found in $1 (one per line; empty if none).
# Exits nonzero only on a genuine tool failure (not on finding duplicates).
find_duplicate_ids() {
  local file="$1"
  local matches rg_status

  set +e
  matches="$(rg '^- \[[ x]\] ([A-Z]+(?:-[A-Z]+)*-[0-9]+):' "$file" -or '$1')"
  rg_status=$?
  set -e

  if [[ $rg_status -gt 1 ]]; then
    return "$rg_status"
  fi

  printf '%s\n' "$matches" | LC_ALL=C sort | uniq -d
}

run_self_test() {
  local tmp_dir clean_fixture dup2_fixture dup3_fixture prose_fixture
  local failures=0

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' RETURN

  clean_fixture="$tmp_dir/clean.md"
  cat >"$clean_fixture" <<'EOF'
- [ ] BUG-001: first bug
- [x] KSP-467: second task
- [ ] DEBT-DIFF-005: third task
- [ ] KSWIFTK-SEMA-0001: fourth task
EOF

  dup2_fixture="$tmp_dir/dup2.md"
  cat >"$dup2_fixture" <<'EOF'
- [ ] BUG-162: first bug using a 2-segment ID
- [x] KSP-467: unrelated task
- [ ] BUG-162: unrelated second bug that collides with the first
EOF

  dup3_fixture="$tmp_dir/dup3.md"
  cat >"$dup3_fixture" <<'EOF'
- [ ] DEBT-DIFF-005: first entry using a 3-segment ID
- [x] KSWIFTK-SEMA-0001: unrelated task
- [ ] DEBT-DIFF-005: second entry that collides with the first
EOF

  prose_fixture="$tmp_dir/prose.md"
  cat >"$prose_fixture" <<'EOF'
- [ ] BUG-200: only definition of this ID
  Discussion text below mentions BUG-200 again but is not a definition line.
See also BUG-200 for background.
EOF

  local got

  got="$(find_duplicate_ids "$clean_fixture")"
  if [[ -n "$got" ]]; then
    echo "self-test FAILED: clean fixture reported a duplicate: $got" >&2
    failures=$((failures + 1))
  fi

  got="$(find_duplicate_ids "$dup2_fixture")"
  if [[ "$got" != "BUG-162" ]]; then
    echo "self-test FAILED: 2-segment duplicate (BUG-162) not detected (got: '$got')" >&2
    failures=$((failures + 1))
  fi

  got="$(find_duplicate_ids "$dup3_fixture")"
  if [[ "$got" != "DEBT-DIFF-005" ]]; then
    echo "self-test FAILED: 3-segment duplicate (DEBT-DIFF-005) not detected (got: '$got')" >&2
    failures=$((failures + 1))
  fi

  got="$(find_duplicate_ids "$prose_fixture")"
  if [[ -n "$got" ]]; then
    echo "self-test FAILED: prose cross-references were incorrectly treated as duplicate definitions: $got" >&2
    failures=$((failures + 1))
  fi

  if [[ "$failures" -gt 0 ]]; then
    echo "check_todo_ids.sh self-test: $failures assertion(s) failed." >&2
    return 1
  fi

  echo "check_todo_ids.sh self-test: all assertions passed."
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "rg is required for TODO ID checks." >&2
  exit 127
fi

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit $?
fi

TODO_FILE="${1:-TODO.md}"

cd "$ROOT_DIR"

if [[ ! -f "$TODO_FILE" ]]; then
  echo "TODO file not found: $TODO_FILE" >&2
  exit 1
fi

duplicates="$(find_duplicate_ids "$TODO_FILE")"

if [[ -n "$duplicates" ]]; then
  echo "Duplicate TODO task IDs found in $TODO_FILE:" >&2
  printf '%s\n' "$duplicates" >&2
  exit 1
fi

echo "No duplicate TODO task IDs found in $TODO_FILE."
