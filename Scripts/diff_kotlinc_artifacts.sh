# Output normalization and failure-artifact persistence helpers for Scripts/diff_kotlinc.sh.
# Sourced by diff_kotlinc.sh (split for readability); not executed directly.

[[ -n "${_KSWIFTK_DIFF_KOTLINC_ARTIFACTS_SH:-}" ]] && return 0
_KSWIFTK_DIFF_KOTLINC_ARTIFACTS_SH=1

_DIFF_KOTLINC_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_DIFF_KOTLINC_HELPER_DIR/lib/common.sh"

normalize_text() {
  tr -d '\r'
}

safe_diff_to_file() {
  local left="$1"
  local right="$2"
  local output="$3"
  if [[ ! -f "$left" || ! -f "$right" ]]; then
    rm -f "$output"
    return 0
  fi
  if ! diff -u "$left" "$right" >"$output"; then
    return 0
  fi
  rm -f "$output"
}

save_runtime_backtrace() {
  local candidate_bin="$1"
  local output="$2"

  if ! command -v "$LLDB_BIN" >/dev/null 2>&1; then
    return 0
  fi

  "$LLDB_BIN" -b -o run -o bt -- "$candidate_bin" >"$output" 2>&1 || true
}

persist_artifacts() {
  local case_path="$1"
  local tmp_dir="$2"
  local result_label="$3"
  local ref_compile_exit="$4"
  local cand_compile_exit="$5"
  local ref_run_exit="$6"
  local cand_run_exit="$7"
  local candidate_only=0
  if is_pr_candidate_only_case "$case_path" || grep -Eq '^[[:space:]]*//[[:space:]]*DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT:' "$case_path"; then
    candidate_only=1
  fi

  mkdir -p "$ARTIFACT_ROOT"

  local case_name
  case_name="$(sanitize_case_name "$case_path")"
  local destination
  destination="$(unique_artifact_destination "$ARTIFACT_ROOT" "$case_name")"

  mv "$tmp_dir" "$destination"

  cp "$case_path" "$destination/input.kt"

  local escaped_kswiftc_flags
  printf -v escaped_kswiftc_flags '%q' "$DIFF_KSWIFTC_FLAGS"

  local comparison_mode="kotlinc-reference"
  local candidate_expected_output=""
  if grep -Eq '^[[:space:]]*//[[:space:]]*DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT:' "$case_path"; then
    comparison_mode="candidate-only-expected-output"
    candidate_expected_output="$(candidate_only_expected_output_file "$case_path" 2>/dev/null || true)"
    if [[ -n "$candidate_expected_output" && -f "$candidate_expected_output" && ! -L "$candidate_expected_output" ]]; then
      cp "$candidate_expected_output" "$destination/expected.stdout"
    fi
  elif is_pr_candidate_only_case "$case_path"; then
    comparison_mode="candidate-only-inline-output"
    candidate_expected_stdout "$case_path" >"$destination/expected.stdout"
  fi

  if [[ $cand_compile_exit -eq 0 ]]; then
    "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KSWIFTC" --no-stdlib --stdlib-library "$STDLIB_ARTIFACT" "${KSWIFTC_ARGS[@]}" --emit kir "$case_path" -o "$destination/candidate.kir" \
      >"$destination/candidate_kir.stdout" \
      2>"$destination/candidate_kir.stderr" || true
  fi
  if [[ $cand_compile_exit -eq 0 && $cand_run_exit -ge 128 ]]; then
    save_runtime_backtrace "$destination/candidate.out" "$destination/backtrace.txt"
  fi

  cat >"$destination/summary.txt" <<EOF
case: $case_path
result: $result_label
comparison_mode: $comparison_mode
artifact_dir: $destination
compile_timeout_seconds: $COMPILE_TIMEOUT
run_timeout_seconds: $RUN_TIMEOUT
script_timeout_seconds: $SCRIPT_TIMEOUT
ref_compile_exit: $ref_compile_exit
candidate_compile_exit: $cand_compile_exit
ref_run_exit: $ref_run_exit
candidate_run_exit: $cand_run_exit
stdlib_artifact: $STDLIB_ARTIFACT
stdlib_manifest_hash: $(stdlib_manifest_hash "$STDLIB_ARTIFACT")
kswiftc: $KSWIFTC
kswiftc_flags: $DIFF_KSWIFTC_FLAGS
kotlinc: $KOTLINC
java: $JAVA_BIN
force_run_skipped: $FORCE_RUN_SKIPPED
clean_runtime_cache: $CLEAN_RUNTIME_CACHE
candidate_only: $candidate_only
EOF

  cat >"$destination/repro.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$ROOT_DIR"
DIFF_STDLIB_LIBRARY="$STDLIB_ARTIFACT" DIFF_KSWIFTC_FLAGS=$escaped_kswiftc_flags DIFF_ARTIFACT_ROOT="$ARTIFACT_ROOT" bash Scripts/diff_kotlinc.sh --no-parallel --keep-temp --force-run-skipped --artifact-root "$ARTIFACT_ROOT" "$case_path"
EOF
  chmod +x "$destination/repro.sh"

  if [[ "$candidate_only" -eq 1 ]]; then
    safe_diff_to_file "$destination/expected_run_stdout.norm" "$destination/cand_run_stdout.norm" "$destination/stdout.diff"
  else
    safe_diff_to_file "$destination/ref_compile_stderr.norm" "$destination/cand_compile_stderr.norm" "$destination/compile_stderr.diff"
    safe_diff_to_file "$destination/ref_run_stdout.norm" "$destination/cand_run_stdout.norm" "$destination/stdout.diff"
    safe_diff_to_file "$destination/ref_run.stderr" "$destination/cand_run.stderr" "$destination/stderr.diff"
  fi

  LAST_ARTIFACT_DIR="$destination"
}
