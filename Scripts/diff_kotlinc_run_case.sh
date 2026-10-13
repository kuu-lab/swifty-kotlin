# Per-case compile/run/compare pipeline for Scripts/diff_kotlinc.sh.
# Sourced by diff_kotlinc.sh (split for readability); not executed directly.

[[ -n "${_KSWIFTK_DIFF_KOTLINC_RUN_CASE_SH:-}" ]] && return 0
_KSWIFTK_DIFF_KOTLINC_RUN_CASE_SH=1

_DIFF_KOTLINC_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib/common.sh
source "$_DIFF_KOTLINC_HELPER_DIR/lib/common.sh"

# Compare normalized ref/candidate run stdout for one case, honoring an
# optional // DIFF_LINE_PATTERN: directive. On mismatch, prints a diff and
# returns 1; the caller is responsible for setting ok=0 in that case.
compare_run_stdout() {
  local tmp_dir="$1"
  local kt_file="$2"
  local line_pattern
  line_pattern="$(get_diff_line_pattern "$kt_file")"
  if [[ -n "$line_pattern" ]]; then
    normalize_stdout_for_diff "$tmp_dir/ref_run_stdout.norm" "$line_pattern" > "$tmp_dir/ref_run_stdout.pat"
    normalize_stdout_for_diff "$tmp_dir/cand_run_stdout.norm" "$line_pattern" > "$tmp_dir/cand_run_stdout.pat"
    if diff -u "$tmp_dir/ref_run_stdout.pat" "$tmp_dir/cand_run_stdout.pat" >/dev/null; then
      return 0
    fi
  else
    if diff -u "$tmp_dir/ref_run_stdout.norm" "$tmp_dir/cand_run_stdout.norm" >/dev/null; then
      return 0
    fi
  fi
  echo "  stdout mismatch:"
  diff -u "$tmp_dir/ref_run_stdout.norm" "$tmp_dir/cand_run_stdout.norm" || true
  return 1
}

run_case() {
  local kt_file="$1"
  local artifact_file="${2:-}"
  if is_candidate_only_from_source_case "$kt_file"; then
    run_candidate_only_from_source_case "$kt_file" "$artifact_file"
    return $?
  fi
  if [[ "$CANDIDATE_ONLY_EXPECTED" -eq 1 ]] \
    || grep -Eq '^[[:space:]]*//[[:space:]]*DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT:' "$kt_file"; then
    local expected_output="$EXPECTED_OUTPUT"
    if [[ -z "$expected_output" ]]; then
      if grep -Eq '^[[:space:]]*//[[:space:]]*DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT:' "$kt_file"; then
        if ! expected_output="$(candidate_only_expected_output_file "$kt_file")"; then
          echo "  invalid DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: use a sidecar filename in the case directory" >&2
          return 1
        fi
      else
        expected_output="${kt_file%.kt}.expected"
      fi
    fi
    local candidate_exit=0
    run_candidate_only_case "$kt_file" "$expected_output" || candidate_exit=$?
    if [[ -n "$artifact_file" ]]; then
      printf '%s\n' "$LAST_ARTIFACT_DIR" >"$artifact_file"
    fi
    return "$candidate_exit"
  fi
  if is_pr_candidate_only_case "$kt_file" \
    && [[ "$(candidate_expected_stdout_directive_count "$kt_file")" -eq 0 ]]; then
    local expected_output="${kt_file%.kt}.expected"
    local candidate_exit=0
    run_candidate_only_case "$kt_file" "$expected_output" || candidate_exit=$?
    if [[ -n "$artifact_file" ]]; then
      printf '%s\n' "$LAST_ARTIFACT_DIR" >"$artifact_file"
    fi
    return "$candidate_exit"
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d -t kswiftk-diff-XXXXXX)"
  LAST_ARTIFACT_DIR="$tmp_dir"

  local ref_jar="$tmp_dir/ref.jar"
  local ref_compile_stdout="$tmp_dir/ref_compile.stdout"
  local ref_compile_stderr="$tmp_dir/ref_compile.stderr"
  local ref_run_stdout="$tmp_dir/ref_run.stdout"
  local ref_run_stderr="$tmp_dir/ref_run.stderr"

  local cand_bin="$tmp_dir/candidate.out"
  local cand_compile_stdout="$tmp_dir/cand_compile.stdout"
  local cand_compile_stderr="$tmp_dir/cand_compile.stderr"
  local cand_run_stdout="$tmp_dir/cand_run.stdout"
  local cand_run_stderr="$tmp_dir/cand_run.stderr"

  : >"$ref_compile_stdout"
  : >"$ref_compile_stderr"
  : >"$ref_run_stdout"
  : >"$ref_run_stderr"
  : >"$cand_run_stdout"
  : >"$cand_run_stderr"

  local ref_compile_exit=0
  local ref_run_exit=0
  local cand_compile_exit=0
  local cand_run_exit=0

  local basename
  basename="$(basename "$kt_file")"
  local candidate_only=0
  local candidate_expected_output=""
  local expected_stdout_valid=1
  local expected_stdout_path="$tmp_dir/expected_run.stdout"
  if grep -Eq '^[[:space:]]*//[[:space:]]*DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT:' "$kt_file"; then
    candidate_only=1
    if ! candidate_expected_output="$(candidate_only_expected_output_file "$kt_file")"; then
      echo "  invalid DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: use a sidecar filename in the case directory" >&2
      rm -rf "$tmp_dir"
      LAST_ARTIFACT_DIR=""
      return 1
    fi
    if [[ ! -f "$candidate_expected_output" || -L "$candidate_expected_output" ]]; then
      echo "  candidate-only expected output must be a regular sidecar file: $candidate_expected_output" >&2
      rm -rf "$tmp_dir"
      LAST_ARTIFACT_DIR=""
      return 1
    fi
    if ! cp "$candidate_expected_output" "$expected_stdout_path"; then
      echo "  failed to read candidate-only expected output: $candidate_expected_output" >&2
      rm -rf "$tmp_dir"
      LAST_ARTIFACT_DIR=""
      return 1
    fi
    echo "  candidate-only expected-output comparison: $candidate_expected_output"
  elif is_pr_candidate_only_case "$kt_file"; then
    candidate_only=1
    local expected_stdout_count
    expected_stdout_count="$(candidate_expected_stdout_directive_count "$kt_file")"
    if [[ "$expected_stdout_count" -gt 0 ]]; then
      candidate_expected_stdout "$kt_file" >"$expected_stdout_path"
    else
      expected_stdout_valid=0
      : >"$expected_stdout_path"
    fi
  fi

  local is_script=0
  if [[ "$basename" == script_* ]]; then
    is_script=1
  fi

  local has_expected_script_exit=0
  local expected_script_exit_directive=""
  local expected_ref_script_exit=""
  local expected_candidate_script_exit=""
  local expected_script_exit_error=""
  if grep -Eq '^[[:space:]]*//[[:space:]]*DIFF_EXPECT_SCRIPT_EXIT:' "$kt_file" 2>/dev/null; then
    has_expected_script_exit=1
    expected_script_exit_directive="$(read_case_directive_flags "$kt_file" 'DIFF_EXPECT_SCRIPT_EXIT')"
    if [[ $is_script -ne 1 ]]; then
      expected_script_exit_error="DIFF_EXPECT_SCRIPT_EXIT is only supported for script_*.kt cases"
    elif [[ ! "$expected_script_exit_directive" =~ ^ref=([0-9]{1,3})[[:space:]]+candidate=([0-9]{1,3})$ ]]; then
      expected_script_exit_error="invalid DIFF_EXPECT_SCRIPT_EXIT directive (expected 'ref=N candidate=N')"
    else
      expected_ref_script_exit=$((10#${BASH_REMATCH[1]}))
      expected_candidate_script_exit=$((10#${BASH_REMATCH[2]}))
      if (( expected_ref_script_exit > 255 || expected_candidate_script_exit > 255 || expected_ref_script_exit == 124 || expected_candidate_script_exit == 124 )); then
        expected_script_exit_error="DIFF_EXPECT_SCRIPT_EXIT values must be process exit codes from 0 to 255, excluding timeout code 124"
      fi
    fi
  fi

  local kotlinc_extra_flags
  kotlinc_extra_flags="$(read_case_directive_flags "$kt_file" 'KOTLINC_FLAGS')"

  local java_extra_flags
  java_extra_flags="$(get_java_extra_flags "$kt_file")"

  if [[ "$candidate_only" -eq 1 ]]; then
    : # The expected output is the reference; no JVM compiler or runtime is used.
  elif [[ $is_script -eq 1 ]]; then
    local kts_tmp="$tmp_dir/${basename%.kt}.kts"
    cp "$kt_file" "$kts_tmp"
    # kotlinc -script bundles compile+run into a single JVM process, so there
    # is no independently observable compile-phase exit to split out here —
    # ref_compile_exit stays 0 and the whole outcome (success, a compile
    # error, a runtime exception, or a timeout) lands in ref_run_exit as one
    # value. Splitting it via a "nonzero exit + empty stdout" heuristic used
    # to misclassify a runtime exception thrown before any output as a
    # compile failure; the comparison below (the is_script branch) instead
    # treats script cases as their own category rather than retrofitting a
    # compile/run split onto a process that never had one.
    if [[ -n "$KOTLINC_CLASSPATH" ]]; then
      # shellcheck disable=SC2086
      "$TIMEOUT_CMD" "$SCRIPT_TIMEOUT" "$KOTLINC" -Xcontext-parameters $kotlinc_extra_flags -classpath "$KOTLINC_CLASSPATH" -script "$kts_tmp" >"$ref_run_stdout" 2>"$ref_run_stderr" || ref_run_exit=$?
    else
      # shellcheck disable=SC2086
      "$TIMEOUT_CMD" "$SCRIPT_TIMEOUT" "$KOTLINC" -Xcontext-parameters $kotlinc_extra_flags -script "$kts_tmp" >"$ref_run_stdout" 2>"$ref_run_stderr" || ref_run_exit=$?
    fi
  elif [[ $candidate_only -eq 0 ]]; then
    local cached_ref_jar=""
    local ref_cache_hit=0
    if [[ -n "$KOTLINC_REF_CACHE_FINGERPRINT" ]]; then
      cached_ref_jar="$(kotlinc_ref_cache_path "$kt_file" "$kotlinc_extra_flags")"
      if [[ -s "$cached_ref_jar" ]] && cp "$cached_ref_jar" "$ref_jar"; then
        ref_cache_hit=1
      fi
    fi

    if [[ $ref_cache_hit -eq 0 ]]; then
      if [[ -n "$KOTLINC_CLASSPATH" ]]; then
        # No -include-runtime: KOTLINC_CLASSPATH includes the stdlib/reflect
        # jars (see resolve_kotlinc_lib_jar above) whenever they could be
        # resolved, so the runtime classes needed by ref_run below are
        # already on the classpath without repackaging them into ref_jar.
        # shellcheck disable=SC2086
        "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KOTLINC" -Xcontext-parameters $kotlinc_extra_flags -classpath "$KOTLINC_CLASSPATH" "$kt_file" -d "$ref_jar" >"$ref_compile_stdout" 2>"$ref_compile_stderr" || ref_compile_exit=$?
      else
        # shellcheck disable=SC2086
        "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KOTLINC" -Xcontext-parameters $kotlinc_extra_flags "$kt_file" -include-runtime -d "$ref_jar" >"$ref_compile_stdout" 2>"$ref_compile_stderr" || ref_compile_exit=$?
      fi
      if [[ $ref_compile_exit -eq 0 && -n "$cached_ref_jar" && -s "$ref_jar" ]]; then
        store_kotlinc_ref_cache "$ref_jar" "$cached_ref_jar"
      fi
    fi
    if [[ $ref_compile_exit -eq 0 ]]; then
      if [[ -n "$KOTLINC_CLASSPATH" ]]; then
        local main_class
        main_class="$(jar_main_class "$ref_jar")"
        if [[ -z "$main_class" ]]; then
          ref_run_exit=1
          echo "Missing Main-Class in reference jar manifest." >"$ref_run_stderr"
        else
          if needs_stdin_eof "$kt_file"; then
            # shellcheck disable=SC2086
            "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$JAVA_BIN" $DIFF_REFERENCE_JAVA_FLAGS $java_extra_flags -cp "$ref_jar:$KOTLINC_CLASSPATH" "$main_class" < /dev/null >"$ref_run_stdout" 2>"$ref_run_stderr" || ref_run_exit=$?
          else
            # shellcheck disable=SC2086
            "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$JAVA_BIN" $DIFF_REFERENCE_JAVA_FLAGS $java_extra_flags -cp "$ref_jar:$KOTLINC_CLASSPATH" "$main_class" >"$ref_run_stdout" 2>"$ref_run_stderr" || ref_run_exit=$?
          fi
        fi
      else
        if needs_stdin_eof "$kt_file"; then
          # shellcheck disable=SC2086
          "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$JAVA_BIN" $DIFF_REFERENCE_JAVA_FLAGS $java_extra_flags -jar "$ref_jar" < /dev/null >"$ref_run_stdout" 2>"$ref_run_stderr" || ref_run_exit=$?
        else
          # shellcheck disable=SC2086
          "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$JAVA_BIN" $DIFF_REFERENCE_JAVA_FLAGS $java_extra_flags -jar "$ref_jar" >"$ref_run_stdout" 2>"$ref_run_stderr" || ref_run_exit=$?
        fi
      fi
    fi
  fi

  "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KSWIFTC" --no-stdlib --stdlib-library "$STDLIB_ARTIFACT" "${KSWIFTC_ARGS[@]}" "$kt_file" -o "$cand_bin" >"$cand_compile_stdout" 2>"$cand_compile_stderr" || cand_compile_exit=$?
  if [[ $cand_compile_exit -eq 0 ]]; then
    if needs_stdin_eof "$kt_file"; then
      "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$cand_bin" < /dev/null >"$cand_run_stdout" 2>"$cand_run_stderr" || cand_run_exit=$?
    else
      "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$cand_bin" >"$cand_run_stdout" 2>"$cand_run_stderr" || cand_run_exit=$?
    fi
  fi

  normalize_text <"$ref_compile_stderr" >"$tmp_dir/ref_compile_stderr.norm"
  normalize_text <"$cand_compile_stderr" >"$tmp_dir/cand_compile_stderr.norm"
  normalize_text <"$ref_run_stdout" >"$tmp_dir/ref_run_stdout.norm" || true
  normalize_text <"$cand_run_stdout" >"$tmp_dir/cand_run_stdout.norm" || true
  normalize_text <"$ref_run_stderr" >"$tmp_dir/ref_run_stderr.norm" || true
  normalize_text <"$cand_run_stderr" >"$tmp_dir/cand_run_stderr.norm" || true
  if [[ $candidate_only -eq 1 ]]; then
    normalize_text <"$expected_stdout_path" >"$tmp_dir/expected_run_stdout.norm" || true
  fi

  local ok=1

  if [[ $candidate_only -eq 1 ]]; then
    if [[ "$expected_stdout_valid" -eq 0 ]]; then
      ok=0
      echo "  candidate-only case requires exactly one // DIFF_EXPECT_STDOUT: directive"
    fi
    if [[ $cand_compile_exit -eq 124 ]]; then
      ok=0
      echo "  candidate compile timed out after ${COMPILE_TIMEOUT}s"
    elif [[ $cand_compile_exit -ne 0 ]]; then
      ok=0
      echo "  candidate compile failed with exit=$cand_compile_exit"
    fi
    if [[ $cand_compile_exit -eq 0 ]]; then
      if [[ $cand_run_exit -eq 124 ]]; then
        ok=0
        echo "  candidate run timed out after ${RUN_TIMEOUT}s"
      elif [[ $cand_run_exit -ne 0 ]]; then
        ok=0
        echo "  candidate run failed with exit=$cand_run_exit"
      elif [[ "$expected_stdout_valid" -eq 1 ]] && ! diff -u "$tmp_dir/expected_run_stdout.norm" "$tmp_dir/cand_run_stdout.norm" >/dev/null; then
        ok=0
        echo "  candidate-only stdout mismatch:"
        diff -u "$tmp_dir/expected_run_stdout.norm" "$tmp_dir/cand_run_stdout.norm" || true
      fi
    fi
  elif [[ $cand_compile_exit -eq 124 ]]; then
    ok=0
    echo "  candidate compile timed out after ${COMPILE_TIMEOUT}s"
  fi

  if [[ $candidate_only -eq 0 && $is_script -eq 1 ]]; then
    # kotlinc -script never had a separate compile phase to compare (see the
    # is_script branch above), so this is not "ref compile exit vs candidate
    # compile exit" — it's ref's single combined exit vs whichever candidate
    # phase actually produced a result (compile failed, or compile succeeded
    # and run finished/failed). Reusing the compile/run mismatch wording here
    # would misreport a ref runtime failure as a "compile exit mismatch"
    # whenever the candidate's real (and separate) compile step succeeds.
    local cand_script_exit=$cand_compile_exit
    if [[ $cand_compile_exit -eq 0 ]]; then
      cand_script_exit=$cand_run_exit
    fi

    if [[ $has_expected_script_exit -eq 1 ]]; then
      if [[ -n "$expected_script_exit_error" ]]; then
        ok=0
        echo "  $expected_script_exit_error"
      elif [[ $ref_run_exit -ne $expected_ref_script_exit || $cand_compile_exit -ne 0 || $cand_run_exit -ne $expected_candidate_script_exit ]]; then
        ok=0
        echo "  script exit expectation mismatch: expected ref=$expected_ref_script_exit candidate=$expected_candidate_script_exit, got ref=$ref_run_exit candidate=$cand_script_exit (candidate compile=$cand_compile_exit run=$cand_run_exit)"
      fi
      if [[ -z "$expected_script_exit_error" ]] && ! compare_run_stdout "$tmp_dir" "$kt_file"; then
        ok=0
      fi
    elif [[ $ref_run_exit -ne $cand_script_exit ]]; then
      ok=0
      echo "  script exit mismatch: ref=$ref_run_exit candidate=$cand_script_exit"
    fi
    if [[ $ref_run_exit -eq 124 ]]; then
      ok=0
      echo "  ref script (compile+run) timed out after ${SCRIPT_TIMEOUT}s"
    fi
    if [[ $cand_compile_exit -ne 124 && $cand_run_exit -eq 124 ]]; then
      ok=0
      echo "  candidate run timed out after ${RUN_TIMEOUT}s"
    fi

    if [[ $has_expected_script_exit -eq 0 && $ref_run_exit -eq 0 && $cand_script_exit -eq 0 ]]; then
      if ! compare_run_stdout "$tmp_dir" "$kt_file"; then
        ok=0
      fi
    elif [[ $has_expected_script_exit -eq 0 && $ref_run_exit -ne 0 && $cand_script_exit -ne 0 && $ref_run_exit -eq $cand_script_exit && $ref_run_exit -ne 124 ]]; then
      # Matching non-zero exit codes do not imply the same failure reason —
      # ref's script may have failed to compile while the candidate's run
      # phase failed for an unrelated reason, or vice versa. Treat this as
      # unverified rather than silently passing (stderr for both sides is
      # included in the FAIL output/artifacts below).
      ok=0
      echo "  note: both ref script and candidate failed with exit=$ref_run_exit; matching exit codes do not verify parity — stderr is reported below; this case will FAIL"
    fi
  elif [[ $candidate_only -eq 0 ]]; then
    if [[ $has_expected_script_exit -eq 1 ]]; then
      ok=0
      echo "  $expected_script_exit_error"
    fi
    if [[ $ref_compile_exit -ne $cand_compile_exit ]]; then
      ok=0
      echo "  compile exit mismatch: ref=$ref_compile_exit candidate=$cand_compile_exit"
    fi
    if [[ $ref_compile_exit -eq 124 ]]; then
      ok=0
      echo "  ref compile timed out after ${COMPILE_TIMEOUT}s"
    fi

    # Matching non-zero compile exits skip the run/stdout comparison below, then
    # the matching-failure branch forces this case to FAIL. Compile stderr is
    # retained in the failure output and artifacts; matching exit codes alone
    # never count as verified parity.
    if [[ $ref_compile_exit -ne 0 && $ref_compile_exit -eq $cand_compile_exit && $ref_compile_exit -ne 124 ]]; then
      echo "  note: both sides failed to compile with exit=$ref_compile_exit; matching exit codes do not verify parity — compile stderr is reported below; this case will FAIL"
    fi

    if [[ $ref_compile_exit -eq 0 && $cand_compile_exit -eq 0 ]]; then
      if [[ $ref_run_exit -ne $cand_run_exit ]]; then
        ok=0
        echo "  run exit mismatch: ref=$ref_run_exit candidate=$cand_run_exit"
      fi
      if [[ $ref_run_exit -eq 124 ]]; then
        ok=0
        echo "  ref run timed out after ${RUN_TIMEOUT}s"
      fi
      if [[ $cand_run_exit -eq 124 ]]; then
        ok=0
        echo "  candidate run timed out after ${RUN_TIMEOUT}s"
      fi
      if ! compare_run_stdout "$tmp_dir" "$kt_file"; then
        ok=0
      fi
    elif [[ $ref_compile_exit -ne 0 && $cand_compile_exit -ne 0 && $ref_compile_exit -eq $cand_compile_exit ]]; then
      # Matching non-zero exit codes do not imply the same failure reason: ref
      # and candidate may be erroring out for entirely unrelated causes. Treat
      # this as unverified rather than silently passing (compile stderr for
      # both sides is included in the FAIL output/artifacts below).
      ok=0
      echo "  both compile failed with exit=$ref_compile_exit (matching exit code alone does not verify parity; compile stderr not compared)"
    fi
  fi

  local artifact_ref_compile_exit="$ref_compile_exit"
  local artifact_ref_run_exit="$ref_run_exit"
  if [[ $candidate_only -eq 1 ]]; then
    artifact_ref_compile_exit="n/a"
    artifact_ref_run_exit="n/a"
  fi

  if [[ $ok -eq 1 ]]; then
    if [[ "$DIFF_LOG_PASS" != "0" && "$DIFF_LOG_PASS" != "false" ]]; then
      if [[ "$candidate_only" -eq 1 ]]; then
        echo "PASS $kt_file (candidate-only expected output)"
      else
        echo "PASS $kt_file"
      fi
    fi
  else
    echo "FAIL $kt_file"
    if [[ $candidate_only -eq 1 ]]; then
      echo "  candidate-only compile stderr:"
      sed -n '1,120p' "$tmp_dir/cand_compile_stderr.norm"
      if [[ $cand_compile_exit -eq 0 ]]; then
        echo "  candidate-only expected stdout:"
        cat "$tmp_dir/expected_run_stdout.norm"
        echo "  candidate-only actual stdout:"
        cat "$tmp_dir/cand_run_stdout.norm"
        echo "  candidate-only run stderr:"
        sed -n '1,120p' "$tmp_dir/cand_run_stderr.norm"
      fi
    else
      if [[ $is_script -eq 1 ]]; then
        # There is no separate ref compile phase for script mode (see the
        # is_script branch above) — kotlinc -script's only stderr output,
        # whether from a compile diagnostic or an uncaught runtime exception,
        # lands in ref_run_stderr.
        echo "  ref script stderr:"
        sed -n '1,120p' "$ref_run_stderr"
      else
        echo "  ref compile stderr:"
        sed -n '1,120p' "$tmp_dir/ref_compile_stderr.norm"
      fi
      echo "  candidate compile stderr:"
      sed -n '1,120p' "$tmp_dir/cand_compile_stderr.norm"
      if [[ $is_script -eq 1 ]]; then
        if [[ $cand_compile_exit -eq 0 ]]; then
          echo "  candidate run stderr:"
          sed -n '1,120p' "$cand_run_stderr"
        fi
      elif [[ $ref_compile_exit -eq 0 && $cand_compile_exit -eq 0 ]]; then
        echo "  ref run stderr:"
        sed -n '1,120p' "$ref_run_stderr"
        echo "  candidate run stderr:"
        sed -n '1,120p' "$cand_run_stderr"
      fi
    fi
  fi

  if [[ $ok -eq 0 ]]; then
    persist_artifacts \
      "$kt_file" \
      "$tmp_dir" \
      "FAIL" \
      "$artifact_ref_compile_exit" \
      "$cand_compile_exit" \
      "$artifact_ref_run_exit" \
      "$cand_run_exit"
    echo "  artifacts: $LAST_ARTIFACT_DIR"
  elif [[ $KEEP_TEMP -eq 0 ]]; then
    rm -rf "$tmp_dir"
    LAST_ARTIFACT_DIR=""
  else
    echo "  artifacts: $tmp_dir"
  fi

  if [[ -n "$artifact_file" ]]; then
    printf '%s\n' "$LAST_ARTIFACT_DIR" >"$artifact_file"
  fi

  return $((1 - ok))
}

run_case_worker() {
  local kt_file="$1"
  local log_path="$2"
  local status_path="$3"
  local artifact_file="$4"

  local case_exit=0
  local status="PASS"
  local artifact=""

  run_case "$kt_file" "$artifact_file" >"$log_path" 2>&1 || case_exit=$?

  if [[ $case_exit -ne 0 ]]; then
    status="FAIL"
  fi

  artifact="$(cat "$artifact_file" 2>/dev/null || true)"
  printf '%s\t%s\n' "$status" "$artifact" >"$status_path"
}
