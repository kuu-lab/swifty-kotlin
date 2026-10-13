# Candidate-only execution lanes for Scripts/diff_kotlinc.sh (expected-output and
# bundled-source modes).
# Sourced by diff_kotlinc.sh (split for readability); not executed directly.

[[ -n "${_KSWIFTK_DIFF_KOTLINC_CANDIDATE_ONLY_SH:-}" ]] && return 0
_KSWIFTK_DIFF_KOTLINC_CANDIDATE_ONLY_SH=1

_DIFF_KOTLINC_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_DIFF_KOTLINC_HELPER_DIR/lib/common.sh"

persist_source_candidate_artifacts() {
  local kt_file="$1"
  local expected_file="$2"
  local tmp_dir="$3"
  local compile_exit="$4"
  local run_exit="$5"

  mkdir -p "$ARTIFACT_ROOT"
  local case_name destination
  case_name="$(sanitize_case_name "$kt_file")-candidate-only"
  destination="$(unique_artifact_destination "$ARTIFACT_ROOT" "$case_name")"
  if [[ -f "$expected_file" ]]; then
    cp "$expected_file" "$tmp_dir/expected.out"
  fi
  mv "$tmp_dir" "$destination"
  cp "$kt_file" "$destination/input.kt"
  safe_diff_to_file "$destination/expected.stdout.norm" "$destination/candidate.stdout.norm" "$destination/stdout.diff"

  # Retain this lane's KIR, crash diagnostics, and runnable reproduction.
  if [[ $compile_exit -eq 0 ]]; then
    KSWIFTK_STDLIB_CACHE_DIR="$destination/stdlib-cache" "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KSWIFTC" --stdlib-from-source "${KSWIFTC_ARGS[@]}" --emit kir "$kt_file" -o "$destination/candidate.kir" \
      >"$destination/candidate_kir.stdout" 2>"$destination/candidate_kir.stderr" || true
    if [[ $run_exit -ge 128 ]]; then
      save_runtime_backtrace "$destination/candidate.out" "$destination/backtrace.txt"
    fi
  fi
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    printf 'cd %q\n' "$ROOT_DIR"
    printf 'KSWIFTC=%q DIFF_KSWIFTC_FLAGS=%q DIFF_ARTIFACT_ROOT=%q bash Scripts/diff_kotlinc.sh --no-parallel --keep-temp --force-run-skipped --compile-timeout %q --run-timeout %q %q\n' \
      "$KSWIFTC" "$DIFF_KSWIFTC_FLAGS" "$ARTIFACT_ROOT" "$COMPILE_TIMEOUT" "$RUN_TIMEOUT" "$kt_file"
  } >"$destination/repro.sh"
  chmod +x "$destination/repro.sh"

  cat >"$destination/summary.txt" <<EOF
case: $kt_file
result: FAIL (candidate-only)
artifact_dir: $destination
compile_timeout_seconds: $COMPILE_TIMEOUT
run_timeout_seconds: $RUN_TIMEOUT
expected_output: $expected_file
candidate_compile_exit: $compile_exit
candidate_run_exit: $run_exit
stdlib_artifact: bundled-sources
kswiftc: $KSWIFTC
kswiftc_flags: $DIFF_KSWIFTC_FLAGS
EOF

  LAST_ARTIFACT_DIR="$destination"
}

run_candidate_only_from_source_case() {
  local kt_file="$1"
  local artifact_file="${2:-}"
  local expected_file="${kt_file%.kt}.expected"
  local tmp_dir candidate_bin compile_exit=0 run_exit=not-run ok=1

  tmp_dir="$(mktemp -d -t kswiftk-candidate-only-XXXXXX)"
  LAST_ARTIFACT_DIR="$tmp_dir"
  candidate_bin="$tmp_dir/candidate.out"

  # Internal source-backed cases can record their oracle as a sidecar or as
  # ordered EXPECT-STDOUT lines. Neither format belongs to the artifact lane.
  if [[ ! -f "$expected_file" ]]; then
    expected_file="$tmp_dir/expected.inline"
    if grep -Eq '^[[:space:]]*//[[:space:]]*EXPECT-STDOUT:' "$kt_file"; then
      awk '/^[[:space:]]*\/\/[[:space:]]*EXPECT-STDOUT:/ {
        sub(/^[[:space:]]*\/\/[[:space:]]*EXPECT-STDOUT:[[:space:]]?/, "")
        print
      }' "$kt_file" >"$expected_file"
    else
      ok=0
      echo "  source candidate-only case needs a .expected sidecar or // EXPECT-STDOUT: lines"
      : >"$expected_file"
    fi
  fi

  KSWIFTK_STDLIB_CACHE_DIR="$tmp_dir/stdlib-cache" "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KSWIFTC" --stdlib-from-source "${KSWIFTC_ARGS[@]}" "$kt_file" -o "$candidate_bin" \
    >"$tmp_dir/candidate_compile.stdout" 2>"$tmp_dir/candidate_compile.stderr" || compile_exit=$?

  if [[ $compile_exit -eq 0 ]]; then
    run_exit=0
    "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$candidate_bin" \
      >"$tmp_dir/candidate.stdout" 2>"$tmp_dir/candidate.stderr" || run_exit=$?
  else
    : >"$tmp_dir/candidate.stdout"
    : >"$tmp_dir/candidate.stderr"
  fi

  normalize_text <"$tmp_dir/candidate.stdout" >"$tmp_dir/candidate.stdout.norm"
  normalize_text <"$expected_file" >"$tmp_dir/expected.stdout.norm"

  if [[ $compile_exit -ne 0 ]]; then
    ok=0
    echo "  candidate compile failed with exit=$compile_exit"
    sed -n '1,120p' "$tmp_dir/candidate_compile.stderr"
  elif [[ $run_exit -ne 0 ]]; then
    ok=0
    if [[ $run_exit -eq 124 ]]; then
      echo "  candidate run timed out after ${RUN_TIMEOUT}s"
    else
      echo "  candidate run failed with exit=$run_exit"
    fi
    sed -n '1,120p' "$tmp_dir/candidate.stderr"
  elif ! diff -u "$tmp_dir/expected.stdout.norm" "$tmp_dir/candidate.stdout.norm" >"$tmp_dir/stdout.diff"; then
    ok=0
    echo "  candidate stdout did not match $expected_file"
    cat "$tmp_dir/stdout.diff"
  fi

  if [[ $ok -eq 1 ]]; then
    if [[ "$DIFF_LOG_PASS" != "0" && "$DIFF_LOG_PASS" != "false" ]]; then
      echo "PASS $kt_file (candidate-only)"
    fi
    if [[ $KEEP_TEMP -eq 0 ]]; then
      rm -rf "$tmp_dir"
      LAST_ARTIFACT_DIR=""
    else
      echo "  artifacts: $tmp_dir"
    fi
  else
    echo "FAIL $kt_file (candidate-only)"
    persist_source_candidate_artifacts "$kt_file" "$expected_file" "$tmp_dir" "$compile_exit" "$run_exit"
    echo "  artifacts: $LAST_ARTIFACT_DIR"
  fi

  if [[ -n "$artifact_file" ]]; then
    printf '%s\n' "$LAST_ARTIFACT_DIR" >"$artifact_file"
  fi

  return $((1 - ok))
}

run_candidate_only_case() {
  local kt_file="$1"
  local expected_output="$2"
  local tmp_dir
  tmp_dir="$(mktemp -d -t kswiftk-candidate-only-XXXXXX)"

  local candidate_bin="$tmp_dir/candidate.out"
  local compile_stdout="$tmp_dir/candidate_compile.stdout"
  local compile_stderr="$tmp_dir/candidate_compile.stderr"
  local run_stdout="$tmp_dir/candidate_run.stdout"
  local run_stderr="$tmp_dir/candidate_run.stderr"
  local candidate_output_norm="$tmp_dir/candidate_output.norm"
  local expected_output_norm="$tmp_dir/expected_output.norm"
  local compile_exit=0
  local run_exit=not-run
  local ok=1
  local artifact=""
  local expected_output_exists=0

  : >"$compile_stdout"
  : >"$compile_stderr"
  : >"$run_stdout"
  : >"$run_stderr"

  if [[ -f "$expected_output" ]]; then
    expected_output_exists=1
    "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KSWIFTC" --no-stdlib --stdlib-library "$STDLIB_ARTIFACT" "${KSWIFTC_ARGS[@]}" "$kt_file" -o "$candidate_bin" \
      >"$compile_stdout" 2>"$compile_stderr" || compile_exit=$?

    if [[ "$compile_exit" -eq 0 ]]; then
      run_exit=0
      if needs_stdin_eof "$kt_file"; then
        "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$candidate_bin" < /dev/null >"$run_stdout" 2>"$run_stderr" || run_exit=$?
      else
        "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$candidate_bin" >"$run_stdout" 2>"$run_stderr" || run_exit=$?
      fi
    fi
  else
    compile_exit=not-run
    run_exit=not-run
  fi

  normalize_text <"$run_stdout" >"$candidate_output_norm"
  if [[ "$expected_output_exists" -eq 1 ]]; then
    normalize_text <"$expected_output" >"$expected_output_norm"
  else
    ok=0
    echo "Candidate-only case is missing its expected output file: $expected_output" >&2
    : >"$expected_output_norm"
  fi

  if [[ "$expected_output_exists" -eq 0 ]]; then
    : # Missing oracles fail without executing the case.
  elif [[ "$compile_exit" -ne 0 ]]; then
    ok=0
    echo "  candidate compile failed with exit=$compile_exit"
    sed -n '1,120p' "$compile_stderr"
  elif [[ "$run_exit" -ne 0 ]]; then
    ok=0
    echo "  candidate run failed with exit=$run_exit"
    sed -n '1,120p' "$run_stderr"
  elif ! diff -u "$expected_output_norm" "$candidate_output_norm"; then
    ok=0
    echo "  candidate stdout did not match expected output"
  fi

  if [[ "$ok" -eq 1 ]]; then
    echo "PASS CANDIDATE-ONLY $kt_file"
    if [[ "$KEEP_TEMP" -eq 0 ]]; then
      rm -rf "$tmp_dir"
    else
      artifact="$tmp_dir"
      echo "  artifacts: $artifact"
    fi
  else
    mkdir -p "$ARTIFACT_ROOT"
    artifact="$(unique_artifact_destination "$ARTIFACT_ROOT" "candidate_only_$(sanitize_case_name "$kt_file")")"
    mv "$tmp_dir" "$artifact"
    cp "$kt_file" "$artifact/input.kt"
    if [[ -f "$expected_output" ]]; then
      cp "$expected_output" "$artifact/expected_output"
    fi
    safe_diff_to_file "$artifact/expected_output.norm" "$artifact/candidate_output.norm" "$artifact/stdout.diff"
    cat >"$artifact/summary.txt" <<EOF
case: $kt_file
result: FAIL
artifact_dir: $artifact
compile_timeout_seconds: $COMPILE_TIMEOUT
run_timeout_seconds: $RUN_TIMEOUT
candidate_compile_exit: $compile_exit
candidate_run_exit: $run_exit
expected_output: $expected_output
stdlib_artifact: $STDLIB_ARTIFACT
stdlib_manifest_hash: $(stdlib_manifest_hash "$STDLIB_ARTIFACT")
kswiftc: $KSWIFTC
kswiftc_flags: $DIFF_KSWIFTC_FLAGS
EOF
    echo "  artifacts: $artifact"
  fi

  LAST_ARTIFACT_DIR="$artifact"
  return $((1 - ok))
}
