#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [TODO-file]

Detect duplicate task IDs in TODO.md.

The check only considers task-definition lines of the form
`- [ ] ID:` or `- [x] ID:`, so cross-references in prose are ignored.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

TODO_FILE="${1:-TODO.md}"

cd "$ROOT_DIR"

if [[ ! -f "$TODO_FILE" ]]; then
  echo "TODO file not found: $TODO_FILE" >&2
  exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "rg is required for TODO ID checks." >&2
  exit 127
fi

set +e
matches="$(rg '^- \[[ x]\] ([A-Z]+-[A-Z-]+-[0-9]+):' "$TODO_FILE" -or '$1')"
rg_status=$?
set -e

if [[ $rg_status -gt 1 ]]; then
  exit "$rg_status"
fi

duplicates="$(printf '%s\n' "$matches" | LC_ALL=C sort | uniq -d)"

if [[ -n "$duplicates" ]]; then
  echo "Duplicate TODO task IDs found in $TODO_FILE:" >&2
  printf '%s\n' "$duplicates" >&2
  exit 1
fi

echo "No duplicate TODO task IDs found in $TODO_FILE."
