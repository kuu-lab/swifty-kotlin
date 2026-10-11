# Case discovery, classification, and directive/skip helpers for Scripts/diff_kotlinc.sh.
# Sourced by diff_kotlinc.sh (split for readability); not executed directly.

[[ -n "${_KSWIFTK_DIFF_KOTLINC_CASES_SH:-}" ]] && return 0
_KSWIFTK_DIFF_KOTLINC_CASES_SH=1

_DIFF_KOTLINC_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_DIFF_KOTLINC_HELPER_DIR/lib/common.sh"

is_pr_candidate_only_case() {
  local kt_file="$1"
  grep -Eq '^[[:space:]]*//[[:space:]]*DIFF_CANDIDATE_ONLY([[:space:]]|$)' "$kt_file"
}

candidate_expected_stdout_directive_count() {
  local kt_file="$1"
  grep -Ec '^[[:space:]]*//[[:space:]]*DIFF_EXPECT_(STDOUT|OUTPUT):' "$kt_file" || true
}

candidate_expected_stdout() {
  local kt_file="$1"
  sed -n \
    -e 's/^[[:space:]]*\/\/[[:space:]]*DIFF_EXPECT_STDOUT:[[:space:]]*//p' \
    -e 's/^[[:space:]]*\/\/[[:space:]]*DIFF_EXPECT_OUTPUT:[[:space:]]*//p' \
    "$kt_file"
}

collect_cases() {
  local path="$1"
  if [[ -f "$path" ]]; then
    printf '%s\n' "$path" | shard_interleave "$DIFF_SHARD_INDEX" "$DIFF_SHARD_COUNT"
  elif [[ -d "$path" ]]; then
    find "$path" -type f -name '*.kt' | sort \
      | shard_interleave "$DIFF_SHARD_INDEX" "$DIFF_SHARD_COUNT"
  else
    echo "Target does not exist: $path" >&2
    return 1
  fi
}

# Emits this shard's cases (interleaved sharding via lib/common.sh;
# DIFF_SHARD_COUNT == 1 emits everything).
collect_cases() {
  local path="$1"
  if [[ -f "$path" ]]; then
    printf '%s\n' "$path" | shard_interleave "$DIFF_SHARD_INDEX" "$DIFF_SHARD_COUNT"
  elif [[ -d "$path" ]]; then
    find "$path" -type f -name '*.kt' | sort \
      | shard_interleave "$DIFF_SHARD_INDEX" "$DIFF_SHARD_COUNT"
  else
    echo "Target does not exist: $path" >&2
    exit 1
  fi
}

is_candidate_only_from_source_case() {
  grep -Eq '^[[:space:]]*//[[:space:]]*DIFF_CANDIDATE_ONLY_FROM_SOURCE([[:space:]:]|$)' "$1"
}

is_pr_candidate_only_case() {
  grep -Eq '^[[:space:]]*//[[:space:]]*DIFF_CANDIDATE_ONLY([[:space:]]|:|$)' "$1"
}

# Resolve the expected-output sidecar named by a candidate-only case. Relative
# paths are anchored to the Kotlin source file so the case is portable across
# callers and CI working directories.
candidate_only_expected_output_file() {
  local case_path="$1"
  local expected_path
  expected_path="$(grep -E '^[[:space:]]*//[[:space:]]*DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT:' "$case_path" 2>/dev/null \
    | head -1 \
    | sed 's/.*DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT:[[:space:]]*//')"
  [[ -n "$expected_path" ]] || return 1

  case "$expected_path" in
    /*|*/*|*\\*|.|..) return 2 ;;
  esac

  local case_dir
  case_dir="$(cd "$(dirname "$case_path")" && pwd)"
  printf '%s/%s\n' "$case_dir" "$expected_path"
}

# Preserve the separate master runner's stdout/stderr sidecars alongside this
# PR's candidate-only marker and expected-output format.
is_master_candidate_only_case() {
  local case_path="$1"
  is_candidate_only_case "$case_path" || return 1
  [[ -f "${case_path%.kt}.expected.stdout" || -f "${case_path%.kt}.expected.stderr" ]]
}

# Number of cases in the target *before* sharding, so an empty shard can be
# distinguished from a genuinely empty target.
count_target_cases() {
  local path="$1"
  if [[ -f "$path" ]]; then
    printf '1'
  elif [[ -d "$path" ]]; then
    find "$path" -type f -name '*.kt' | wc -l | tr -d '[:space:]'
  else
    printf '0'
  fi
}

# Decide what an empty case set means. A genuinely empty target is an error, but
# an empty shard (sharding on, with every case assigned to other shards) is a
# normal no-op that must exit 0 so the aggregate gate stays green.
handle_empty_cases() {
  if (( DIFF_SHARD_COUNT > 1 )) && (( $(count_target_cases "$TARGET") > 0 )); then
    echo "No cases assigned to shard ${DIFF_SHARD_INDEX}/${DIFF_SHARD_COUNT}; nothing to do."
    echo "Summary: total=0 failed=0 passed=0 skipped=0"
    exit 0
  fi
  echo "No .kt files found." >&2
  exit 1
}

# Cases that need stdin=EOF (e.g. readLine() returning null)
needs_stdin_eof() {
  local kt_file="$1"
  grep -Eq '^[[:space:]]*//[[:space:]]*DIFF_STDIN_EOF\b' "$kt_file"
}

# Extract DIFF_LINE_PATTERN regex for lines that may differ (e.g. object identity hash)
# Format: // DIFF_LINE_PATTERN: <regex>
get_diff_line_pattern() {
  local kt_file="$1"
  grep -E '^[[:space:]]*//[[:space:]]*DIFF_LINE_PATTERN:' "$kt_file" 2>/dev/null | head -1 | sed 's/.*DIFF_LINE_PATTERN:[[:space:]]*//'
}

# Extract extra JVM flags (e.g. -ea) from // JAVA_FLAGS: directives in the test
# file. These are passed to the `java` invocation that runs the reference jar,
# before -cp/-jar so they are parsed as JVM options rather than program args.
# Format: // JAVA_FLAGS: <flags>
get_java_extra_flags() {
  local kt_file="$1"
  grep -E '^[[:space:]]*//[[:space:]]*JAVA_FLAGS:' "$kt_file" 2>/dev/null | sed 's/.*JAVA_FLAGS:[[:space:]]*//' | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

# Normalize stdout: replace lines matching pattern with placeholder for diff.
# The pattern is passed through the environment (not awk -v) so backslashes in
# the regex are not mangled by awk's escape-sequence processing.
normalize_stdout_for_diff() {
  local file="$1"
  local pattern="$2"
  if [[ -z "$pattern" ]]; then
    cat "$file"
  else
    DIFF_LINE_PATTERN_RE="$pattern" awk '
      $0 ~ ENVIRON["DIFF_LINE_PATTERN_RE"] { print "__DIFF_PATTERN_MATCH__"; next }
      { print }
    ' "$file"
  fi
}

should_skip_regular_diff_case() {
  should_skip_diff_case "$1" "$FORCE_RUN_SKIPPED"
}

print_skipped_case() {
  echo "SKIP $1 (// SKIP-DIFF)"
}
