#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
DIFF_KSWIFTC_FLAGS="${DIFF_KSWIFTC_FLAGS:-}"
COMPILE_TIMEOUT="${DIFF_COMPILE_TIMEOUT:-120}"
RUN_TIMEOUT="${DIFF_RUN_TIMEOUT:-10}"
STDLIB_COMPILE_TIMEOUT="${DIFF_STDLIB_COMPILE_TIMEOUT:-600}"
TIMEOUT_CMD="${TIMEOUT:-timeout}"
ARTIFACT_ROOT="${DIFF_ARTIFACT_ROOT:-$ROOT_DIR/.artifacts/candidate_only}"
STDLIB_LIBRARY="${DIFF_STDLIB_LIBRARY:-}"
KEEP_TEMP="${DIFF_CANDIDATE_ONLY_KEEP_TEMP:-0}"

declare -a KSWIFTC_ARGS=()
if [[ -n "$DIFF_KSWIFTC_FLAGS" ]]; then
  read -r -a KSWIFTC_ARGS <<< "$DIFF_KSWIFTC_FLAGS"
fi

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options] <file-or-dir>

Run Kotlin cases marked // CANDIDATE-ONLY without kotlinc or a JVM reference.
Each case needs either a sibling .expected.stdout file (successful execution)
or a sibling .expected.stderr file (expected candidate compile failure).

Options:
  --kswiftc <path>          Candidate compiler (default: .build/debug/kswiftc)
  --compile-timeout <secs>  Candidate compile timeout (default: 120)
  --run-timeout <secs>      Candidate program timeout (default: 10)
  --stdlib-timeout <secs>   Bundled stdlib build timeout (default: 600)
  --stdlib-library <path>   Reuse an existing KSwiftKStdlib.kklib
  --artifact-root <path>    Stdlib and failure artifacts directory
  --keep-temp               Keep successful per-case temporary directories
  -h, --help                Show this help
USAGE
}

TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kswiftc)
      shift
      [[ $# -gt 0 ]] || { echo "--kswiftc requires a path" >&2; exit 2; }
      KSWIFTC="$1"
      ;;
    --compile-timeout)
      shift
      [[ $# -gt 0 ]] || { echo "--compile-timeout requires seconds" >&2; exit 2; }
      COMPILE_TIMEOUT="$1"
      ;;
    --run-timeout)
      shift
      [[ $# -gt 0 ]] || { echo "--run-timeout requires seconds" >&2; exit 2; }
      RUN_TIMEOUT="$1"
      ;;
    --stdlib-timeout)
      shift
      [[ $# -gt 0 ]] || { echo "--stdlib-timeout requires seconds" >&2; exit 2; }
      STDLIB_COMPILE_TIMEOUT="$1"
      ;;
    --stdlib-library)
      shift
      [[ $# -gt 0 ]] || { echo "--stdlib-library requires a path" >&2; exit 2; }
      STDLIB_LIBRARY="$1"
      ;;
    --artifact-root)
      shift
      [[ $# -gt 0 ]] || { echo "--artifact-root requires a path" >&2; exit 2; }
      ARTIFACT_ROOT="$1"
      ;;
    --keep-temp)
      KEEP_TEMP=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$TARGET" ]]; then
        echo "Only one file-or-dir target is supported" >&2
        exit 2
      fi
      TARGET="$1"
      ;;
  esac
  shift
done

if [[ -z "$TARGET" ]]; then
  usage >&2
  exit 2
fi
CALLER_DIR="$(pwd)"
if [[ "$TARGET" != /* ]]; then
  TARGET="$CALLER_DIR/$TARGET"
fi
if [[ "$KSWIFTC" == */* && "$KSWIFTC" != /* ]]; then
  KSWIFTC="$CALLER_DIR/$KSWIFTC"
fi
if [[ "$ARTIFACT_ROOT" != /* ]]; then
  ARTIFACT_ROOT="$CALLER_DIR/$ARTIFACT_ROOT"
fi
if [[ -n "$STDLIB_LIBRARY" && "$STDLIB_LIBRARY" != /* ]]; then
  STDLIB_LIBRARY="$CALLER_DIR/$STDLIB_LIBRARY"
fi
if ! [[ "$COMPILE_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "compile timeout must be a positive integer: $COMPILE_TIMEOUT" >&2
  exit 2
fi
if ! [[ "$RUN_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "run timeout must be a positive integer: $RUN_TIMEOUT" >&2
  exit 2
fi
if ! [[ "$STDLIB_COMPILE_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "stdlib compile timeout must be a positive integer: $STDLIB_COMPILE_TIMEOUT" >&2
  exit 2
fi
if ! command -v "$KSWIFTC" >/dev/null 2>&1; then
  echo "kswiftc not found: $KSWIFTC (build it with 'swift build')" >&2
  exit 1
fi
if ! command -v "$TIMEOUT_CMD" >/dev/null 2>&1; then
  echo "timeout command not found: $TIMEOUT_CMD" >&2
  exit 1
fi
cd "$ROOT_DIR"

declare -a CASES=()
if [[ -f "$TARGET" ]]; then
  if is_candidate_only_case "$TARGET"; then
    CASES+=("$TARGET")
  else
    echo "Case is not marked // CANDIDATE-ONLY: $TARGET" >&2
    exit 2
  fi
elif [[ -d "$TARGET" ]]; then
  while IFS= read -r case_path; do
    if is_candidate_only_case "$case_path"; then
      CASES+=("$case_path")
    fi
  done < <(find "$TARGET" -type f -name '*.kt' | sort)
else
  echo "Target does not exist: $TARGET" >&2
  exit 2
fi

if [[ ${#CASES[@]} -eq 0 ]]; then
  echo "No // CANDIDATE-ONLY cases found under: $TARGET" >&2
  exit 1
fi

if [[ -n "$STDLIB_LIBRARY" ]]; then
  if [[ ! -d "$STDLIB_LIBRARY" || ! -f "$STDLIB_LIBRARY/manifest.json" ]]; then
    echo "Stdlib library does not exist or is missing manifest.json: $STDLIB_LIBRARY" >&2
    exit 1
  fi
  STDLIB_ARTIFACT="$STDLIB_LIBRARY"
else
  mkdir -p "$ARTIFACT_ROOT"
  STDLIB_ARTIFACT="$ARTIFACT_ROOT/KSwiftKStdlib.kklib"
  stdlib_stdout="$ARTIFACT_ROOT/stdlib_build.stdout"
  stdlib_stderr="$ARTIFACT_ROOT/stdlib_build.stderr"
  stdlib_build_exit=0
  echo "Building candidate stdlib artifact: $STDLIB_ARTIFACT"
  "$TIMEOUT_CMD" "$STDLIB_COMPILE_TIMEOUT" "$KSWIFTC" --stdlib-only --emit library -o "$STDLIB_ARTIFACT" >"$stdlib_stdout" 2>"$stdlib_stderr" || stdlib_build_exit=$?
  if [[ $stdlib_build_exit -ne 0 ]]; then
    if [[ $stdlib_build_exit -eq 124 ]]; then
      echo "Failed to build candidate stdlib artifact: timed out after ${STDLIB_COMPILE_TIMEOUT}s" >&2
    else
      echo "Failed to build candidate stdlib artifact: exit=$stdlib_build_exit" >&2
    fi
    cat "$stdlib_stdout" "$stdlib_stderr" >&2
    exit 1
  fi
fi

normalize_text() {
  tr -d '\r' < "$1"
}

case_stdin_eof() {
  grep -q '^[[:space:]]*//[[:space:]]*DIFF_STDIN_EOF' "$1"
}

run_case() {
  local case_path="$1"
  local expected_base="${case_path%.kt}.expected"
  local expected_stdout="$expected_base.stdout"
  local expected_stderr="$expected_base.stderr"
  local case_temp candidate_bin compile_stdout compile_stderr run_stdout run_stderr
  local compile_exit=0 run_exit=0 ok=1 case_arg case_abs

  if [[ -f "$expected_stdout" && -f "$expected_stderr" ]]; then
    echo "FAIL $case_path: choose one expected sidecar (.expected.stdout or .expected.stderr)"
    return 1
  fi
  if [[ ! -f "$expected_stdout" && ! -f "$expected_stderr" ]]; then
    echo "FAIL $case_path: missing .expected.stdout or .expected.stderr sidecar"
    return 1
  fi

  case_temp="$(mktemp -d -t kswiftk-candidate-only-XXXXXX)"
  candidate_bin="$case_temp/candidate.out"
  compile_stdout="$case_temp/candidate_compile.stdout"
  compile_stderr="$case_temp/candidate_compile.stderr"
  run_stdout="$case_temp/candidate_run.stdout"
  run_stderr="$case_temp/candidate_run.stderr"

  case_abs="$(cd "$(dirname "$case_path")" && pwd)/$(basename "$case_path")"
  if [[ "$case_abs" == "$ROOT_DIR/"* ]]; then
    case_arg="${case_abs#"$ROOT_DIR"/}"
  else
    case_arg="$case_abs"
  fi

  "$TIMEOUT_CMD" "$COMPILE_TIMEOUT" "$KSWIFTC" --no-stdlib --stdlib-library "$STDLIB_ARTIFACT" "${KSWIFTC_ARGS[@]}" "$case_arg" -o "$candidate_bin" >"$compile_stdout" 2>"$compile_stderr" || compile_exit=$?
  normalize_text "$compile_stderr" > "$case_temp/candidate_compile.stderr.norm"

  if [[ -f "$expected_stderr" ]]; then
    normalize_text "$expected_stderr" > "$case_temp/expected.stderr.norm"
    if [[ $compile_exit -eq 0 ]]; then
      ok=0
      echo "  expected candidate compilation to fail, but it succeeded"
    elif [[ $compile_exit -eq 124 ]]; then
      ok=0
      echo "  candidate compile timed out after ${COMPILE_TIMEOUT}s"
    elif [[ $compile_exit -ne 1 ]]; then
      ok=0
      echo "  candidate compile failed with unexpected exit=$compile_exit (expected 1)"
    elif ! diff -u "$case_temp/expected.stderr.norm" "$case_temp/candidate_compile.stderr.norm"; then
      ok=0
      echo "  candidate compile diagnostics did not match $expected_stderr"
    fi
  else
    if [[ $compile_exit -ne 0 ]]; then
      ok=0
      if [[ $compile_exit -eq 124 ]]; then
        echo "  candidate compile timed out after ${COMPILE_TIMEOUT}s"
      else
        echo "  candidate compile failed with exit=$compile_exit"
        cat "$case_temp/candidate_compile.stderr.norm"
      fi
    else
      if case_stdin_eof "$case_path"; then
        "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$candidate_bin" < /dev/null >"$run_stdout" 2>"$run_stderr" || run_exit=$?
      else
        "$TIMEOUT_CMD" "$RUN_TIMEOUT" "$candidate_bin" >"$run_stdout" 2>"$run_stderr" || run_exit=$?
      fi
      normalize_text "$run_stdout" > "$case_temp/candidate_run.stdout.norm"
      normalize_text "$expected_stdout" > "$case_temp/expected.stdout.norm"
      if [[ $run_exit -ne 0 ]]; then
        ok=0
        echo "  candidate run failed with exit=$run_exit"
        cat "$run_stderr"
      elif ! diff -u "$case_temp/expected.stdout.norm" "$case_temp/candidate_run.stdout.norm"; then
        ok=0
        echo "  candidate output did not match $expected_stdout"
      fi
    fi
  fi

  if [[ $ok -eq 1 ]]; then
    echo "PASS $case_path (candidate-only)"
    if [[ "$KEEP_TEMP" != "1" ]]; then
      rm -rf "$case_temp"
    else
      echo "  artifacts: $case_temp"
    fi
    return 0
  fi

  echo "FAIL $case_path (candidate-only)"
  echo "  artifacts: $case_temp"
  return 1
}

TOTAL=0
FAILED=0
for case_path in "${CASES[@]}"; do
  TOTAL=$((TOTAL + 1))
  if ! run_case "$case_path"; then
    FAILED=$((FAILED + 1))
  fi
done

echo "Summary: total=$TOTAL failed=$FAILED passed=$((TOTAL - FAILED))"
if [[ $FAILED -ne 0 ]]; then
  exit 1
fi
