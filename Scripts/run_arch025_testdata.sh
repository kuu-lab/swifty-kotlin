#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="${ARCH025_MANIFEST:-$ROOT_DIR/Tests/ARCH-025/manifest.tsv}"
LEDGER="$ROOT_DIR/Tests/ARCH-025/ledger.tsv"
KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
WRITE_LEDGER=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--write-ledger] [--kswiftc <path>]

Run the local ARCH-025 fixture subset serially.

Options:
  --write-ledger       Replace Tests/ARCH-025/ledger.tsv with deterministic results.
  --kswiftc <path>    Use a specific kswiftc executable.
  -h, --help          Show this help.

The runner intentionally does not run in CI and does not invoke kotlinc.
USAGE
}

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write-ledger)
      WRITE_LEDGER=1
      ;;
    --kswiftc)
      shift
      [[ $# -gt 0 ]] || { echo "--kswiftc requires a path" >&2; exit 1; }
      KSWIFTC="$1"
      ;;
    --kswiftc=*)
      KSWIFTC="${1#*=}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

[[ -f "$MANIFEST" ]] || { echo "Manifest not found: $MANIFEST" >&2; exit 1; }

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/arch025-run.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT

ledger_rows=""
failures=0
total=0
pass_count=0
fail_count=0
unsupported_count=0

while IFS=$'\t' read -r record_id kind upstream_path fixture_path expected availability sha256 rationale; do
  [[ -z "$record_id" || "${record_id#\#}" != "$record_id" ]] && continue
  total=$((total + 1))
  fixture="$ROOT_DIR/$fixture_path"
  if [[ ! -f "$fixture" ]]; then
    status="fail"
    detail="missing_fixture"
    compile_exit="-"
    run_exit="-"
  elif [[ "$(hash_file "$fixture")" != "$sha256" ]]; then
    status="fail"
    detail="fixture_hash_mismatch"
    compile_exit="-"
    run_exit="-"
  elif [[ "$availability" == "unsupported" ]]; then
    status="unsupported"
    detail="unsupported:$rationale"
    compile_exit="-"
    run_exit="-"
  else
    case_dir="$TEMP_ROOT/$record_id"
    mkdir -p "$case_dir"
    input_file="$case_dir/input.kt"
    output_file="$case_dir/program"
    stdout_file="$case_dir/stdout.txt"
    stderr_file="$case_dir/stderr.txt"
    status=""

    if [[ "$kind" == "diagnostics" ]]; then
      # Remove JetBrains diagnostic markup only in the temporary input.
      sed -E 's/<![^>]*>//g' "$fixture" >"$input_file"
    elif [[ "$kind" == "codegen" ]]; then
      # Kotlin compiler box tests expose box() instead of a process entry point.
      {
        cat "$fixture"
        printf '\nfun main() { print(box()) }\n'
      } >"$input_file"
    else
      status="fail"
      detail="unknown_kind"
      compile_exit="-"
      run_exit="-"
    fi

    if [[ "$status" != "fail" ]]; then
      if [[ -x "$KSWIFTC" ]]; then
        if "$KSWIFTC" "$input_file" -o "$output_file" >"$stdout_file" 2>"$stderr_file"; then
          compile_exit=0
        else
          compile_exit=$?
        fi
      else
        compile_exit=127
        printf 'kswiftc not executable: %s\n' "$KSWIFTC" >"$stderr_file"
      fi

      run_exit="-"
      if [[ "$expected" == "reject" ]]; then
        if [[ "$compile_exit" -ne 0 ]]; then
          status="pass"
          detail="expected_rejection"
        else
          status="fail"
          detail="unexpected_acceptance"
        fi
      elif [[ "$expected" == box:* ]]; then
        expected_output="${expected#box:}"
        if [[ "$compile_exit" -ne 0 ]]; then
          status="fail"
          detail="compile_exit_${compile_exit}"
        elif "$output_file" >"$stdout_file" 2>"$stderr_file"; then
          run_exit=0
          actual_output="$(tr -d '\r' <"$stdout_file")"
          if [[ "$actual_output" == "$expected_output" ]]; then
            status="pass"
            detail="box_output_${expected_output}"
          else
            status="fail"
            detail="box_output_mismatch"
          fi
        else
          run_exit=$?
          status="fail"
          detail="run_exit_${run_exit}"
        fi
      else
        status="fail"
        detail="unknown_expectation"
      fi
    fi

  fi

  case "$status" in
    pass)
      pass_count=$((pass_count + 1))
      ;;
    fail)
      fail_count=$((fail_count + 1))
      failures=$((failures + 1))
      ;;
    unsupported)
      unsupported_count=$((unsupported_count + 1))
      ;;
    *)
      fail_count=$((fail_count + 1))
      failures=$((failures + 1))
      status="fail"
      detail="invalid_status"
      ;;
  esac

  ledger_rows="${ledger_rows}${record_id}\t${kind}\t${fixture_path}\t${expected}\t${status}\t${compile_exit}\t${run_exit}\t${detail}\t${sha256}\n"
  printf '%s\t%s\t%s\n' "$status" "$record_id" "$detail"
done < "$MANIFEST"

ledger_header='# ARCH-025 ledger; generated by Scripts/run_arch025_testdata.sh.'
ledger_revision='# Upstream revision: 679366a83f99851b42f64795f10ed803ff011c73 (v2.3.10)'
ledger_columns=$'id\tkind\tfixture\texpected\tstatus\tcompile_exit\trun_exit\tdetail\tsha256'
if [[ $WRITE_LEDGER -eq 1 ]]; then
  ledger_temp="$TEMP_ROOT/ledger.tsv"
  {
    printf '%s\n' "$ledger_header"
    printf '%s\n' "$ledger_revision"
    printf '%s\n' "$ledger_columns"
    printf '%b' "$ledger_rows"
  } >"$ledger_temp"
  mv "$ledger_temp" "$LEDGER"
  echo "Wrote $LEDGER"
else
  printf '%s\n' "$ledger_header" "$ledger_revision" "$ledger_columns"
  printf '%b' "$ledger_rows"
fi

printf 'summary total=%s pass=%s fail=%s unsupported=%s\n' "$total" "$pass_count" "$fail_count" "$unsupported_count"
if [[ $failures -ne 0 ]]; then
  exit 1
fi
