#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

parallel_mode="${SWIFT_TEST_PARALLEL:-}"
workers_override="${SWIFT_TEST_WORKERS:-}"
build_jobs_override="${SWIFT_TEST_BUILD_JOBS:-}"

has_parallel_flag=false
has_workers_flag=false
has_jobs_flag=false
supports_parallel_flags=true
for arg in "$@"; do
    case "$arg" in
        --parallel|--no-parallel)
            has_parallel_flag=true
            ;;
        --num-workers|--num-workers=*)
            has_workers_flag=true
            ;;
        -j|--jobs|--jobs=*)
            has_jobs_flag=true
            ;;
        --list-tests|-l|list|last)
            supports_parallel_flags=false
            ;;
    esac
done

declare -a command=(swift test)

if [[ "$has_jobs_flag" == false ]]; then
    build_jobs="$build_jobs_override"
    if [[ -z "$build_jobs" ]]; then
        build_jobs="$(detect_workers)"
    fi
    if [[ -n "$build_jobs" ]]; then
        command+=(-j "$build_jobs")
    fi
fi

if [[ "$supports_parallel_flags" == true ]]; then
    if [[ "$parallel_mode" == "0" || "$parallel_mode" == "false" ]]; then
        if [[ "$has_parallel_flag" == false ]]; then
            command+=(--no-parallel)
        fi
    else
        if [[ "$has_parallel_flag" == false ]]; then
            command+=(--parallel)
        fi

        if [[ "$has_workers_flag" == false ]]; then
            workers="$workers_override"
            if [[ -z "$workers" ]]; then
                workers="$(detect_workers)"
            fi
            if [[ -n "$workers" ]]; then
                command+=(--num-workers "$workers")
            fi
        fi
    fi
fi

command+=("$@")

# ---------------------------------------------------------------------------
# Color helpers (disabled in CI unless NO_COLOR is unset and terminal present)
# ---------------------------------------------------------------------------
if [[ -t 2 && "${NO_COLOR:-}" == "" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BOLD='' RESET=''
fi

# ---------------------------------------------------------------------------
# Run swift test, capturing output while streaming it to the terminal.
# Parse failure lines to build a grouped summary.
# ---------------------------------------------------------------------------
tmpout="$(mktemp "${TMPDIR:-/tmp}/swift_test_out.XXXXXX")"
trap 'rm -f "$tmpout"' EXIT

test_exit=0
"${command[@]}" 2>&1 | tee "$tmpout" || test_exit=$?

# ---------------------------------------------------------------------------
# Parse failures from swift test output.
# XCTest lines: "Test Case '-[Suite.Class method]' failed"
# Swift Testing lines: "FAILED: Suite/test"  or  "✗ Suite.test"
# ---------------------------------------------------------------------------
declare -a failed_tests=()

while IFS= read -r line; do
    # XCTest: "Test Case '-[CompilerCoreTests.LexerTests testFoo]' failed (0.123 seconds)"
    if [[ "$line" =~ "Test Case '-["([^]]+)"]' failed" ]]; then
        failed_tests+=("${BASH_REMATCH[1]}")
        continue
    fi
    # Swift Testing: lines starting with "FAILED:" (uppercase)
    if [[ "$line" =~ ^[[:space:]]*FAILED:[[:space:]]*(.+)$ ]]; then
        failed_tests+=("${BASH_REMATCH[1]}")
        continue
    fi
    # Swift Testing: "✗ Suite.test" or "◇ ... ✗"
    if [[ "$line" =~ [✗✖][[:space:]]+([A-Za-z0-9_.]+[A-Za-z0-9_/.:]+) ]]; then
        failed_tests+=("${BASH_REMATCH[1]}")
        continue
    fi
done < "$tmpout"

# Deduplicate while preserving order
declare -a unique_failures=()
declare -A _dedup_seen=()
for t in "${failed_tests[@]+"${failed_tests[@]}"}"; do
    if [[ -z "${_dedup_seen[$t]:-}" ]]; then
        _dedup_seen[$t]=1
        unique_failures+=("$t")
    fi
done
unset _dedup_seen

# ---------------------------------------------------------------------------
# Emit grouped failure summary
# ---------------------------------------------------------------------------
emit_failure_summary() {
    local count="${#unique_failures[@]}"
    if (( count == 0 )); then
        if (( test_exit == 0 )); then
            printf >&2 "\n${GREEN}${BOLD}All tests passed.${RESET}\n"
        fi
        return
    fi

    printf >&2 "\n${RED}${BOLD}── Test Failures (%d) ──────────────────────────────────────────${RESET}\n" "$count"

    # Group by suite prefix (first component before '.' or '/').
    local suite
    local -a suite_order=()
    local -A suite_entries=()
    for t in "${unique_failures[@]}"; do
        suite="${t%%[./]*}"
        if [[ -z "${suite_entries[$suite]:-}" ]]; then
            suite_order+=("$suite")
        fi
        suite_entries[$suite]+="${t}"$'\n'
    done

    for suite in "${suite_order[@]}"; do
        printf >&2 "\n${YELLOW}${BOLD}[%s]${RESET}\n" "$suite"
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            printf >&2 "  ${RED}✗${RESET} %s\n" "$entry"
            # Emit GitHub Actions error annotation (one per failure)
            if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
                printf '::error title=Test Failure::%s\n' "$entry"
            fi
        done <<< "${suite_entries[$suite]}"
    done

    printf >&2 "\n${RED}${BOLD}%d test(s) failed.${RESET}\n" "$count"

    # Hint for golden test failures
    for t in "${unique_failures[@]}"; do
        if [[ "$t" == *Golden* || "$t" == *golden* || "$t" == *matchesGolden* ]]; then
            printf >&2 "\n${YELLOW}Hint: golden mismatch detected — regenerate with:${RESET}\n"
            printf >&2 "  %s\n" "$GOLDEN_UPDATE_CMD"
            break
        fi
    done

    # Emit GitHub Actions step summary table
    if [[ "${GITHUB_ACTIONS:-}" == "true" && -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        {
            printf '## Swift Test Failures (%d)\n\n' "$count"
            printf '| Suite | Test |\n'
            printf '|-------|------|\n'
            for t in "${unique_failures[@]}"; do
                local suite="${t%%[./]*}"
                printf '| `%s` | `%s` |\n' "$suite" "$t"
            done
            printf '\n'
        } >> "$GITHUB_STEP_SUMMARY"
    fi
}

emit_failure_summary

exit "$test_exit"
