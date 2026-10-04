#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: diff_kotlinc_ci_summary.sh --report <path> [--summary <path>] [--artifact-root <path>] [--diff-lines <n>]

Renders the TSV report from Scripts/diff_kotlinc.sh as markdown (GitHub Step
Summary compatible).

Options:
  --report <path>        TSV report emitted by Scripts/diff_kotlinc.sh
  --summary <path>       Optional markdown output path
  --artifact-root <path> Root directory for failure artifacts (used for detailed diffs)
  --diff-lines <n>       Max diff lines to embed per case (default: 30, 0 = unlimited)
  -h, --help             Show this help
USAGE
}

REPORT_PATH=""
SUMMARY_PATH="${GITHUB_STEP_SUMMARY:-}"
ARTIFACT_ROOT="${DIFF_ARTIFACT_ROOT:-}"
DIFF_MAX_LINES=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report)
      shift
      REPORT_PATH="${1:-}"
      ;;
    --summary)
      shift
      SUMMARY_PATH="${1:-}"
      ;;
    --artifact-root)
      shift
      ARTIFACT_ROOT="${1:-}"
      ;;
    --diff-lines)
      shift
      DIFF_MAX_LINES="${1:-$DIFF_MAX_LINES}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -z "$REPORT_PATH" ]]; then
  echo "--report is required" >&2
  usage
  exit 1
fi

if [[ ! -f "$REPORT_PATH" ]]; then
  echo "Report file not found: $REPORT_PATH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helper: read a file and truncate to DIFF_MAX_LINES lines (0 = unlimited)
# ---------------------------------------------------------------------------
read_limited() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return
  fi
  if [[ "$DIFF_MAX_LINES" -le 0 ]]; then
    cat "$file"
    return
  fi
  awk -v max="$DIFF_MAX_LINES" '
    NR <= max { print }
    END { if (NR > max) printf "... (%d more lines)\n", NR - max }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: resolve artifact directory for a failed case, writing the result
# into the caller's variable named by $1 (avoids a subshell fork per case).
# Accepts the artifact_dir from the TSV, falling back to ARTIFACT_ROOT lookup.
# ---------------------------------------------------------------------------
resolve_artifact_dir() {
  local -n __resolved="$1"
  local test_case="$2"
  local tsv_artifact_dir="$3"

  if [[ -n "$tsv_artifact_dir" && -d "$tsv_artifact_dir" ]]; then
    __resolved="$tsv_artifact_dir"
    return
  fi

  if [[ -n "$ARTIFACT_ROOT" ]]; then
    local candidate="$ARTIFACT_ROOT/$(sanitize_case_name "$test_case")"
    if [[ -d "$candidate" ]]; then
      __resolved="$candidate"
      return
    fi
  fi

  __resolved=""
}

# ---------------------------------------------------------------------------
# Parse the TSV report. Non-passing, non-skipped cases (FAIL, or any
# unrecognized status) are treated as failures and recorded as
# "test_case\tartifact_dir" entries in failed_entries.
# ---------------------------------------------------------------------------
total=0
passed=0
failed=0
skipped=0
failed_entries=()

while IFS=$'\t' read -r test_case status artifact_dir; do
  [[ -n "${test_case:-}" ]] || continue
  total=$((total + 1))
  case "${status:-}" in
    PASS)
      passed=$((passed + 1))
      continue
      ;;
    SKIP)
      skipped=$((skipped + 1))
      continue
      ;;
  esac

  failed=$((failed + 1))
  adir=""
  resolve_artifact_dir adir "$test_case" "${artifact_dir:-}"
  failed_entries+=("$test_case"$'\t'"$adir")

  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    # Workflow commands must be a single line on stdout for GitHub Actions.
    if [[ "${status:-}" == "FAIL" ]]; then
      printf '::error file=%s,title=kotlinc diff::diff regression failed for this case\n' "$test_case"
    else
      printf '::warning file=%s,title=kotlinc diff::unknown status %s\n' "$test_case" "${status:-UNKNOWN}"
    fi
  fi
done < "$REPORT_PATH"

# ---------------------------------------------------------------------------
# Helper: print one <details>-wrapped fenced code block. Pass use_limit=0 to
# cat the file in full instead of truncating to DIFF_MAX_LINES.
# ---------------------------------------------------------------------------
emit_detail_block() {
  local summary="$1" fence_lang="$2" content_file="$3" use_limit="${4:-1}"
  printf '\n'
  printf '%s\n' "<details><summary>${summary}</summary>"
  printf '\n'
  printf '%s\n' "\`\`\`${fence_lang}"
  if [[ "$use_limit" == "1" ]]; then
    read_limited "$content_file"
  else
    cat "$content_file"
  fi
  printf '%s\n' '```'
  printf '\n'
  printf '%s\n' '</details>'
}

# ---------------------------------------------------------------------------
# Emit Markdown (for GitHub Step Summary / console)
# ---------------------------------------------------------------------------
emit_markdown() {
  printf '%s\n' "## kotlinc Diff Regression Summary"
  printf '\n'
  printf '%s\n' "| Metric | Count |"
  printf '%s\n' "|--------|-------|"
  printf '| Total   | %d |\n' "$total"
  printf '| Passed  | %d |\n' "$passed"
  printf '| Failed  | %d |\n' "$failed"
  printf '| Skipped | %d |\n' "$skipped"

  if (( failed > 0 )); then
    printf '\n'
    printf '%s\n' "### Failed Cases"
    printf '\n'

    local entry test_case adir
    for entry in "${failed_entries[@]}"; do
      IFS=$'\t' read -r test_case adir <<< "$entry"

      printf '#### `%s`\n' "$test_case"
      if [[ -n "$adir" ]]; then
        printf '%s\n' "- Artifacts: \`${adir}\`"
      fi

      # Embed stdout diff if available
      if [[ -n "$adir" && -f "$adir/stdout.diff" && -s "$adir/stdout.diff" ]]; then
        emit_detail_block 'stdout diff' 'diff' "$adir/stdout.diff"
        printf '\n'
        printf '%s\n' '> **Golden update candidate**: stdout mismatch detected.'
        printf '> To regenerate: `%s`\n' "$GOLDEN_UPDATE_CMD"
      fi

      # Embed compile stderr diff if available
      if [[ -n "$adir" && -f "$adir/compile_stderr.diff" && -s "$adir/compile_stderr.diff" ]]; then
        emit_detail_block 'compile stderr diff' 'diff' "$adir/compile_stderr.diff"
      fi

      # Embed summary.txt if available
      if [[ -n "$adir" && -f "$adir/summary.txt" ]]; then
        emit_detail_block 'case summary' '' "$adir/summary.txt" 0
      fi

      printf '\n'
    done
  fi
}

# ---------------------------------------------------------------------------
# Main output
# ---------------------------------------------------------------------------
if [[ -n "$SUMMARY_PATH" ]]; then
  emit_markdown | tee -a "$SUMMARY_PATH"
else
  emit_markdown
fi
