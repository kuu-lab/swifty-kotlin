#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]:-$0}")"
KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
KOTLINC="${KOTLINC:-kotlinc}"
JAVA_BIN="${JAVA_BIN:-java}"
TIMEOUT_CMD="${TIMEOUT:-timeout}"
DIFF_REQUIRE_JDK21="${DIFF_REQUIRE_JDK21:-1}"
DIFF_LOG_PASS="${DIFF_LOG_PASS:-1}"
COMPILE_TIMEOUT="${DIFF_COMPILE_TIMEOUT:-120}"
KEEP_TEMP=0
REPORT_PATH=""
ARTIFACT_ROOT="${DIFF_ARTIFACT_ROOT:-$ROOT_DIR/.artifacts/diff_diagnostics}"
FORCE_RUN_SKIPPED=0
SELF_TEST=0
TARGET=""
TMP_ROOT=""
TOTAL=0
FAILED=0
SKIPPED=0
SELF_TEST_TMP=""

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options] <file-or-dir>

Options:
  --kswiftc <path>       Path to kswiftc binary (default: .build/debug/kswiftc)
  --kotlinc <path>       Path to Kotlin compiler (default: kotlinc)
  --java <path>          Path to java command used for the JDK check (default: java)
  --compile-timeout <s>  Per-compiler timeout (default: \$DIFF_COMPILE_TIMEOUT or 120)
  --keep-temp            Keep per-case temporary directories until process exit
  --report <path>        Write a TSV report (case, status, artifact directory)
  --artifact-root <path> Persist failure artifacts under this directory
  --force-run-skipped    Run cases marked with // SKIP-DIFF or // KSWIFTK_DIFF_IGNORE
  --self-test            Run shell-level acceptance/rejection parity regression tests
  -h, --help             Show this help

Environment:
  DIFF_REQUIRE_JDK21     Require JDK 21 or newer (default: 1; set to 0 locally)
  DIFF_LOG_PASS          If 0 or false, omit PASS lines (default: 1)
  DIFF_COMPILE_TIMEOUT   Per-compiler timeout in seconds
  TIMEOUT                timeout command (Coreutils timeout on macOS)

Case directives:
  // EXPECT-ACCEPT        Both compilers must accept the source (default)
  // EXPECT-REJECT        Both compilers must reject the source and report the same error lines
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kswiftc)
      shift
      [[ $# -gt 0 ]] || { echo "--kswiftc requires an argument" >&2; exit 1; }
      KSWIFTC="$1"
      ;;
    --kswiftc=*)
      KSWIFTC="${1#*=}"
      ;;
    --kotlinc)
      shift
      [[ $# -gt 0 ]] || { echo "--kotlinc requires an argument" >&2; exit 1; }
      KOTLINC="$1"
      ;;
    --kotlinc=*)
      KOTLINC="${1#*=}"
      ;;
    --java)
      shift
      [[ $# -gt 0 ]] || { echo "--java requires an argument" >&2; exit 1; }
      JAVA_BIN="$1"
      ;;
    --java=*)
      JAVA_BIN="${1#*=}"
      ;;
    --compile-timeout)
      shift
      [[ $# -gt 0 ]] || { echo "--compile-timeout requires an argument" >&2; exit 1; }
      COMPILE_TIMEOUT="$1"
      ;;
    --compile-timeout=*)
      COMPILE_TIMEOUT="${1#*=}"
      ;;
    --keep-temp)
      KEEP_TEMP=1
      ;;
    --report)
      shift
      [[ $# -gt 0 ]] || { echo "--report requires an argument" >&2; exit 1; }
      REPORT_PATH="$1"
      ;;
    --report=*)
      REPORT_PATH="${1#*=}"
      ;;
    --artifact-root)
      shift
      [[ $# -gt 0 ]] || { echo "--artifact-root requires an argument" >&2; exit 1; }
      ARTIFACT_ROOT="$1"
      ;;
    --artifact-root=*)
      ARTIFACT_ROOT="${1#*=}"
      ;;
    --force-run-skipped)
      FORCE_RUN_SKIPPED=1
      ;;
    --self-test)
      SELF_TEST=1
      ;;
    --parallel|--no-parallel)
      # Diagnostics are intentionally serial in the first stage to keep the gate lightweight.
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -* )
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [[ -n "$TARGET" ]]; then
        echo "Only one file-or-dir argument is supported." >&2
        exit 1
      fi
      TARGET="$1"
      ;;
  esac
  shift
done

if ! [[ "$COMPILE_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "compile timeout must be a positive integer: $COMPILE_TIMEOUT" >&2
  exit 1
fi

if [[ $SELF_TEST -eq 1 && -n "$TARGET" ]]; then
  echo "--self-test cannot be combined with a target." >&2
  exit 1
fi

sanitize_case_name() {
  local case_path="$1"
  case_path="${case_path#$ROOT_DIR/}"
  printf '%s' "$case_path" | tr '/[:space:]' '__' | tr -cd '[:alnum:]_.-'
}

expected_outcome() {
  local case_path="$1"
  local reject_count accept_count
  reject_count="$(grep -Ec '^[[:space:]]*//[[:space:]]*EXPECT-REJECT([[:space:]]|$)' "$case_path" || true)"
  accept_count="$(grep -Ec '^[[:space:]]*//[[:space:]]*EXPECT-ACCEPT([[:space:]]|$)' "$case_path" || true)"
  if (( reject_count > 0 && accept_count > 0 )); then
    echo "A case cannot contain both EXPECT-REJECT and EXPECT-ACCEPT." >&2
    return 1
  fi
  if (( reject_count > 1 || accept_count > 1 )); then
    echo "A case may contain at most one EXPECT directive." >&2
    return 1
  fi
  if (( reject_count == 1 )); then
    printf 'reject\n'
  else
    printf 'accept\n'
  fi
}

normalize_error_lines() {
  local diagnostics_path="$1"
  {
    grep -Ei '(^|[[:space:]])error([[:space:]:]|$)' "$diagnostics_path" || true
  } | sed -nE 's/.*:([0-9]+):[0-9]+:.*$/\1/p' | sort -n -u
}

lines_display() {
  local lines_path="$1"
  if [[ -s "$lines_path" ]]; then
    tr '\n' ',' <"$lines_path" | sed 's/,$//'
  else
    printf '<empty>'
  fi
}

is_timeout_exit() {
  local exit_code="$1"
  [[ "$exit_code" -eq 124 || "$exit_code" -eq 137 ]]
}

report_case() {
  local case_path="$1" status="$2" artifact_dir="$3" ref_exit="$4" candidate_exit="$5" ref_lines="$6" candidate_lines="$7"
  if [[ -n "$REPORT_PATH" ]]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$case_path" "$status" "$artifact_dir" "$ref_exit" "$candidate_exit" "$ref_lines" "$candidate_lines" >>"$REPORT_PATH"
  fi
}

persist_failure() {
  local case_path="$1" tmp_dir="$2" result_reason="$3" ref_exit="$4" candidate_exit="$5" ref_lines="$6" candidate_lines="$7"
  mkdir -p "$ARTIFACT_ROOT"

  local destination="$ARTIFACT_ROOT/$(sanitize_case_name "$case_path")"
  local suffix=1
  while [[ -e "$destination" ]]; do
    destination="$ARTIFACT_ROOT/$(sanitize_case_name "$case_path")_$suffix"
    suffix=$((suffix + 1))
  done
  mv "$tmp_dir" "$destination"
  cp "$case_path" "$destination/input.kt"
  printf '%s\n' "$ref_lines" >"$destination/ref_error_lines.txt"
  printf '%s\n' "$candidate_lines" >"$destination/candidate_error_lines.txt"
  cat >"$destination/summary.txt" <<EOF
case: $case_path
result: FAIL
reason: $result_reason
ref_compile_exit: $ref_exit
candidate_compile_exit: $candidate_exit
ref_error_lines: $(lines_display "$destination/ref_error_lines.txt")
candidate_error_lines: $(lines_display "$destination/candidate_error_lines.txt")
compile_timeout_seconds: $COMPILE_TIMEOUT
kswiftc: $KSWIFTC
kotlinc: $KOTLINC
java: $JAVA_BIN
EOF
  cat >"$destination/repro.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd $(printf '%q' "$ROOT_DIR")
DIFF_REQUIRE_JDK21=$(printf '%q' "$DIFF_REQUIRE_JDK21") \
  KSWIFTC=$(printf '%q' "$KSWIFTC") KOTLINC=$(printf '%q' "$KOTLINC") \
  bash Scripts/diff_diagnostics.sh --no-parallel --keep-temp \
    --artifact-root $(printf '%q' "$ARTIFACT_ROOT") $(printf '%q' "$case_path")
EOF
  chmod +x "$destination/repro.sh"
  printf '%s' "$destination"
}

run_case() {
  local case_path="$1"
  local tmp_dir="$TMP_ROOT/$(sanitize_case_name "$case_path")"
  mkdir -p "$tmp_dir"

  local ref_exit=0 candidate_exit=0
  local flags expectation result_reason result_status artifact_dir=""
  flags="$(get_kotlinc_extra_flags "$case_path")"
  if ! expectation="$(expected_outcome "$case_path")"; then
    result_reason="invalid expectation directives"
    result_status="FAIL"
    artifact_dir="$(persist_failure "$case_path" "$tmp_dir" "$result_reason" 2 2 '' '')"
    echo "FAIL $case_path (invalid expectation directives)"
    report_case "$case_path" "$result_status" "$artifact_dir" 2 2 '<empty>' '<empty>'
    return 1
  fi

  # Keep reference and candidate diagnostics separate so artifacts preserve the raw compiler output.
  # shellcheck disable=SC2086
  "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KOTLINC" -Xcontext-parameters $flags "$case_path" \
    -d "$tmp_dir/reference.jar" >"$tmp_dir/reference.stdout" 2>"$tmp_dir/reference.stderr" || ref_exit=$?
  "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KSWIFTC" --emit kir "$case_path" \
    -o "$tmp_dir/candidate.kir" >"$tmp_dir/candidate.stdout" 2>"$tmp_dir/candidate.stderr" || candidate_exit=$?

  cat "$tmp_dir/reference.stdout" "$tmp_dir/reference.stderr" >"$tmp_dir/reference.diagnostics"
  cat "$tmp_dir/candidate.stdout" "$tmp_dir/candidate.stderr" >"$tmp_dir/candidate.diagnostics"
  normalize_error_lines "$tmp_dir/reference.diagnostics" >"$tmp_dir/reference.error_lines"
  normalize_error_lines "$tmp_dir/candidate.diagnostics" >"$tmp_dir/candidate.error_lines"

  local ref_lines candidate_lines
  ref_lines="$(lines_display "$tmp_dir/reference.error_lines")"
  candidate_lines="$(lines_display "$tmp_dir/candidate.error_lines")"

  # Two non-zero exits are not enough for parity; both sides need usable, equal error line sets.
  if is_timeout_exit "$ref_exit" || is_timeout_exit "$candidate_exit"; then
    result_reason="compiler timeout"
  elif [[ "$expectation" == "accept" && "$ref_exit" -ne 0 && "$candidate_exit" -ne 0 ]]; then
    result_reason="both compilers rejected an EXPECT-ACCEPT case"
  elif [[ "$ref_exit" -eq 0 && "$candidate_exit" -eq 0 && "$expectation" == "reject" ]]; then
    result_reason="both compilers accepted an EXPECT-REJECT case"
  elif [[ ("$ref_exit" -eq 0 && "$candidate_exit" -ne 0) || ("$ref_exit" -ne 0 && "$candidate_exit" -eq 0) ]]; then
    result_reason="compile acceptance mismatch (reference=$([[ "$ref_exit" -eq 0 ]] && printf accepted || printf rejected), candidate=$([[ "$candidate_exit" -eq 0 ]] && printf accepted || printf rejected))"
  elif [[ "$ref_exit" -ne 0 && "$candidate_exit" -ne 0 && ( ! -s "$tmp_dir/reference.error_lines" || ! -s "$tmp_dir/candidate.error_lines" ) ]]; then
    result_reason="a rejected compile produced no normalizable error line"
  elif [[ "$ref_exit" -ne 0 && "$candidate_exit" -ne 0 && "$ref_lines" != "$candidate_lines" ]]; then
    result_reason="error line set mismatch (reference=$ref_lines, candidate=$candidate_lines)"
  else
    result_reason=""
  fi

  if [[ -z "$result_reason" ]]; then
    result_status="PASS"
    if [[ "$DIFF_LOG_PASS" != "0" && "$DIFF_LOG_PASS" != "false" ]]; then
      echo "PASS $case_path"
    fi
    report_case "$case_path" "$result_status" "" "$ref_exit" "$candidate_exit" "$ref_lines" "$candidate_lines"
    if [[ $KEEP_TEMP -eq 0 ]]; then
      rm -rf "$tmp_dir"
    fi
    return 0
  fi

  result_status="FAIL"
  artifact_dir="$(persist_failure "$case_path" "$tmp_dir" "$result_reason" "$ref_exit" "$candidate_exit" "$ref_lines" "$candidate_lines")"
  echo "FAIL $case_path"
  echo "  $result_reason"
  echo "  compile exits: reference=$ref_exit candidate=$candidate_exit"
  echo "  reference error lines: $ref_lines"
  echo "  candidate error lines: $candidate_lines"
  echo "  artifact: $artifact_dir"
  report_case "$case_path" "$result_status" "$artifact_dir" "$ref_exit" "$candidate_exit" "$ref_lines" "$candidate_lines"
  return 1
}

run_self_test() {
  local self_tmp
  self_tmp="$(mktemp -d -t kswiftk-diagnostics-self-test-XXXXXX)"
  SELF_TEST_TMP="$self_tmp"
  trap 'rm -rf "${SELF_TEST_TMP:-}"' EXIT

  local ref_fake="$self_tmp/fake-kotlinc" candidate_fake="$self_tmp/fake-kswiftc"
  cat >"$ref_fake" <<'FAKE_REF'
#!/usr/bin/env bash
set -eu
source_file=""
for argument in "$@"; do
  if [[ "$argument" == *.kt ]]; then source_file="$argument"; break; fi
done
case "$(basename "$source_file")" in
  accept.kt) exit 0 ;;
  reject_same.kt|reject_candidate_accept.kt|reject_lines.kt)
    printf '%s\n' "$source_file:2:1: error: fake reference diagnostic" >&2
    exit 1
    ;;
esac
exit 2
FAKE_REF
  cat >"$candidate_fake" <<'FAKE_CANDIDATE'
#!/usr/bin/env bash
set -eu
source_file=""
for argument in "$@"; do
  if [[ "$argument" == *.kt ]]; then source_file="$argument"; break; fi
done
case "$(basename "$source_file")" in
  accept.kt) exit 0 ;;
  reject_same.kt)
    printf '%s\n' "$source_file:2:3: error KSWIFTK-SEMA-TEST: fake candidate diagnostic" >&2
    exit 1
    ;;
  reject_candidate_accept.kt) exit 0 ;;
  reject_lines.kt)
    printf '%s\n' "$source_file:3:3: error KSWIFTK-SEMA-TEST: fake candidate diagnostic" >&2
    exit 1
    ;;
esac
exit 2
FAKE_CANDIDATE
  chmod +x "$ref_fake" "$candidate_fake"

  printf '%s\n' '// EXPECT-ACCEPT' 'fun main() {}' >"$self_tmp/accept.kt"
  printf '%s\n' '// EXPECT-REJECT' 'val broken = ' >"$self_tmp/reject_same.kt"
  printf '%s\n' '// EXPECT-REJECT' 'val broken = ' >"$self_tmp/reject_candidate_accept.kt"
  printf '%s\n' '// EXPECT-REJECT' 'val broken = ' >"$self_tmp/reject_lines.kt"

  local case_path output
  for case_path in accept.kt reject_same.kt; do
    output="$self_tmp/$case_path.out"
    if ! DIFF_REQUIRE_JDK21=0 "$SCRIPT_PATH" --no-parallel --compile-timeout 5 \
      --kswiftc "$candidate_fake" --kotlinc "$ref_fake" --artifact-root "$self_tmp/artifacts" \
      "$self_tmp/$case_path" >"$output" 2>&1; then
      echo "self-test expected PASS but failed: $case_path" >&2
      cat "$output" >&2
      return 1
    fi
  done

  for case_path in reject_candidate_accept.kt reject_lines.kt; do
    output="$self_tmp/$case_path.out"
    if DIFF_REQUIRE_JDK21=0 "$SCRIPT_PATH" --no-parallel --compile-timeout 5 \
      --kswiftc "$candidate_fake" --kotlinc "$ref_fake" --artifact-root "$self_tmp/artifacts" \
      "$self_tmp/$case_path" >"$output" 2>&1; then
      echo "self-test expected FAIL but passed: $case_path" >&2
      cat "$output" >&2
      return 1
    fi
  done
  echo "PASS diff_diagnostics.sh --self-test"
  trap - EXIT
  rm -rf "$self_tmp"
}

if [[ $SELF_TEST -eq 1 ]]; then
  run_self_test
  exit 0
fi

if [[ -z "$TARGET" ]]; then
  usage
  exit 1
fi

if [[ ! -e "$TARGET" ]]; then
  echo "Target does not exist: $TARGET" >&2
  exit 1
fi
if ! [[ -x "$KSWIFTC" ]]; then
  echo "kswiftc not found or not executable: $KSWIFTC" >&2
  exit 1
fi
if ! command -v "$KOTLINC" >/dev/null 2>&1; then
  echo "kotlinc command not found: $KOTLINC" >&2
  exit 1
fi
if ! command -v "$JAVA_BIN" >/dev/null 2>&1; then
  echo "java command not found: $JAVA_BIN" >&2
  exit 1
fi
require_timeout_cmd_or_exit "$TIMEOUT_CMD"

require_jdk21_or_exit "$JAVA_BIN" "diagnostic diff gate"

TMP_ROOT="$(mktemp -d -t kswiftk-diagnostics-XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT
if [[ -n "$REPORT_PATH" ]]; then
  printf 'case\tstatus\tartifact_dir\tref_exit\tcandidate_exit\tref_error_lines\tcandidate_error_lines\n' >"$REPORT_PATH"
fi

case_list="$TMP_ROOT/cases.list"
if [[ -f "$TARGET" ]]; then
  printf '%s\n' "$TARGET" >"$case_list"
else
  find "$TARGET" -type f -name '*.kt' -print | LC_ALL=C sort >"$case_list"
fi
if [[ ! -s "$case_list" ]]; then
  echo "No .kt files found." >&2
  exit 1
fi

echo "=== diff_diagnostics Configuration ==="
echo "Mode: compile acceptance and normalized error line sets"
echo "Compile timeout: ${COMPILE_TIMEOUT}s"
echo "JDK requirement: ${DIFF_REQUIRE_JDK21}"
echo "Force run skipped: $FORCE_RUN_SKIPPED"
echo "Target: $TARGET"
echo "========================================"

while IFS= read -r case_path; do
  if should_skip_case "$case_path"; then
    echo "SKIP $case_path (// SKIP-DIFF)"
    SKIPPED=$((SKIPPED + 1))
    if [[ -n "$REPORT_PATH" ]]; then
      printf '%s\tSKIP\t\t\t\t\t\n' "$case_path" >>"$REPORT_PATH"
    fi
    continue
  fi
  TOTAL=$((TOTAL + 1))
  if ! run_case "$case_path"; then
    FAILED=$((FAILED + 1))
  fi
done <"$case_list"

echo "Summary: total=$TOTAL failed=$FAILED passed=$((TOTAL - FAILED)) skipped=$SKIPPED"
if [[ $FAILED -ne 0 ]]; then
  exit 1
fi
