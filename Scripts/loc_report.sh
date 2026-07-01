#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<USAGE
Usage: $(basename "$0")

Emit refactoring guard metrics as TSV:
  metric<TAB>scope<TAB>value

Metrics:
  loc_by_directory                         Physical lines in tracked files, grouped by top-level directory
  header_helpers_synthetic_total_lines     Physical lines in HeaderHelpers+Synthetic*.swift files
  kk_literal_count                         Occurrences of string literals beginning with "kk_ in Swift/Kotlin sources
  interner_resolve_literal_comparison_count Occurrences of interner.resolve == "..." in Swift sources
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

cd "$ROOT_DIR"

count_lines() {
  if [[ $# -eq 0 ]]; then
    printf '0\n'
    return
  fi

  awk 'END { print NR + 0 }' "$@"
}

count_regex_occurrences() {
  local pattern="$1"
  shift

  if [[ $# -eq 0 ]]; then
    printf '0\n'
    return
  fi

  { grep -hEo "$pattern" "$@" || true; } | awk 'END { print NR + 0 }'
}

emit_directory_loc() {
  local tracked_files=()
  while IFS= read -r file; do
    if [[ -f "$file" ]]; then
      tracked_files+=("$file")
    fi
  done < <(git ls-files)

  if [[ ${#tracked_files[@]} -eq 0 ]]; then
    return
  fi

  awk '
    FNR == 1 {
      dir = FILENAME
      if (index(dir, "/") > 0) {
        sub(/\/.*/, "", dir)
      } else {
        dir = "."
      }
    }
    { totals[dir] += 1 }
    END {
      for (dir in totals) {
        printf "%s\t%d\n", dir, totals[dir]
      }
    }
  ' "${tracked_files[@]}" \
    | LC_ALL=C sort \
    | awk -F '\t' '{ printf "loc_by_directory\t%s\t%s\n", $1, $2 }'
}

SYNTHETIC_HEADER_FILES=()
while IFS= read -r file; do
  SYNTHETIC_HEADER_FILES+=("$file")
done < <(git ls-files 'Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift' | LC_ALL=C sort)

SWIFT_AND_KOTLIN_FILES=()
while IFS= read -r file; do
  SWIFT_AND_KOTLIN_FILES+=("$file")
done < <(git ls-files '*.swift' '*.kt' | LC_ALL=C sort)

SWIFT_FILES=()
while IFS= read -r file; do
  SWIFT_FILES+=("$file")
done < <(git ls-files '*.swift' | LC_ALL=C sort)

printf 'metric\tscope\tvalue\n'
emit_directory_loc
printf 'header_helpers_synthetic_total_lines\tSources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift\t%s\n' \
  "$(count_lines "${SYNTHETIC_HEADER_FILES[@]}")"
printf 'kk_literal_count\tSwift/Kotlin sources\t%s\n' \
  "$(count_regex_occurrences '"kk_[^"]*"' "${SWIFT_AND_KOTLIN_FILES[@]}")"
printf 'interner_resolve_literal_comparison_count\tSwift sources\t%s\n' \
  "$(count_regex_occurrences 'interner\.resolve[[:space:]]*==[[:space:]]*"[^"]+"' "${SWIFT_FILES[@]}")"
