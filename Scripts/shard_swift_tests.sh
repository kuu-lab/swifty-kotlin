#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'USAGE'
Usage:
  shard_swift_tests.sh --mode dynamic --list-filter <regex> \
      --shard-index N --shard-count N [-- swift_test.sh-args...]

  shard_swift_tests.sh --mode static --tests-dir <path> --target-prefix <Module> \
      --shard-index N --shard-count N [-- swift_test.sh-args...]

Splits a full-swift-tests matrix entry into --shard-count interleaved shards
and runs Scripts/swift_test.sh with a --filter that selects only this
shard's share, so multiple CI jobs can split one slow test target.

Modes:
  dynamic   Lists concrete test identifiers via `swift test list --skip-build`
            (requires the target to already be built), filters the list with
            <list-filter>, and shards at the individual-test level. Safe for pure
            XCTest targets, where `swift test list` prints the documented
            "Module.Class/method" specifier for every test. Do NOT use this
            mode for targets that mix in Swift Testing (@Suite/@Test), since
            this script does not depend on knowing that framework's list
            output format.

  static    Extracts test suite type names by scanning test sources under
            --tests-dir for XCTestCase classes and Swift Testing @Suite
            declarations, then shards at the suite level: each shard's
            --filter selects
            `^<prefix>\.(Type1|Type2|...)(/|$)`. If extraction finds no
            candidates at all, the last shard falls back to running the full
            target prefix so a misconfigured path does not silently skip the
            entire target.

Options:
  --mode <dynamic|static>   Sharding mode (required)
  --list-filter <regex>     (dynamic) regex passed to `swift test list --filter`
  --tests-dir <path>        (static) directory to grep test sources from
  --target-prefix <name>    (static) module prefix for the --filter regex
  --shard-index <n>         0-based shard index (default: 0)
  --shard-count <n>         Total shard count (default: 1 = no sharding;
                             the raw --list-filter/target-prefix filter is
                             used unsharded in this case)
  -h, --help                Show this help

Remaining args (after `--`, or any unrecognized args) are forwarded to
Scripts/swift_test.sh, e.g. -Xswiftc flags. --skip-build is always added.
USAGE
}

mode=""
list_filter=""
tests_dir=""
target_prefix=""
shard_index=0
shard_count=1
declare -a passthrough=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            mode="$2"; shift 2 ;;
        --list-filter)
            list_filter="$2"; shift 2 ;;
        --tests-dir)
            tests_dir="$2"; shift 2 ;;
        --target-prefix)
            target_prefix="$2"; shift 2 ;;
        --shard-index)
            shard_index="$2"; shift 2 ;;
        --shard-count)
            shard_count="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        --)
            shift
            passthrough+=("$@")
            break ;;
        *)
            passthrough+=("$1"); shift ;;
    esac
done

run_swift_test() {
    bash "$SCRIPT_DIR/swift_test.sh" --skip-build "$@" "${passthrough[@]}"
}

run_filter_chunks() {
    local total=$(( $# / 2 ))
    local chunk=1
    local status=0
    local flag pattern

    if (( total == 0 )); then
        return 0
    fi

    while (( $# > 0 )); do
        flag="$1"
        pattern="$2"
        shift 2

        # SwiftPM 6.2 does not reliably combine repeated --filter flags,
        # so each chunk must run as its own swift test invocation.
        echo "shard_swift_tests.sh: running filter chunk ${chunk}/${total}." >&2
        run_swift_test "$flag" "$pattern" || status=$?
        chunk=$(( chunk + 1 ))
    done

    return "$status"
}

case "$mode" in
    dynamic)
        [[ -n "$list_filter" ]] || { echo "shard_swift_tests.sh: --list-filter is required for --mode dynamic" >&2; exit 1; }
        ;;
    static)
        [[ -n "$tests_dir" && -n "$target_prefix" ]] || { echo "shard_swift_tests.sh: --tests-dir and --target-prefix are required for --mode static" >&2; exit 1; }
        ;;
    *)
        echo "shard_swift_tests.sh: --mode must be 'dynamic' or 'static'" >&2
        exit 1
        ;;
esac

if (( shard_count <= 1 )); then
    if [[ "$mode" == "dynamic" ]]; then
        run_swift_test --filter "$list_filter"
    else
        run_swift_test --filter "^${target_prefix}\\."
    fi
    exit $?
fi

# ---------------------------------------------------------------------------
# Mode: dynamic — shard at the individual-test level via `swift test list`.
# ---------------------------------------------------------------------------
if [[ "$mode" == "dynamic" ]]; then
    echo "shard_swift_tests.sh: listing tests matching '$list_filter'..." >&2
    # `swift test list` does not honor --filter on every SwiftPM version.
    # List everything and apply the requested shard prefix locally.
    mapfile -t all_tests < <(
        swift test list --skip-build \
            | awk -v filter="$list_filter" '$0 ~ filter { print }' \
            | sort
    )

    total="${#all_tests[@]}"
    if (( total == 0 )); then
        echo "shard_swift_tests.sh: no tests matched '$list_filter'; nothing to run." >&2
        exit 0
    fi

    declare -a shard_tests=()
    for (( i = 0; i < total; i++ )); do
        if (( i % shard_count == shard_index )); then
            shard_tests+=("${all_tests[$i]}")
        fi
    done

    echo "shard_swift_tests.sh: shard $shard_index/$shard_count selects ${#shard_tests[@]} of $total tests." >&2

    if (( ${#shard_tests[@]} == 0 )); then
        echo "shard_swift_tests.sh: shard $shard_index has no tests; skipping." >&2
        exit 0
    fi

    # Test identifiers here are XCTest specifiers ("Module.Class/method"):
    # only alphanumerics, '_', '.', and '/'. Escape '.' so it is matched
    # literally rather than as the regex wildcard; no other characters in
    # this charset are regex metacharacters.
    #
    # A single --filter regex alternating every selected test can exceed
    # Linux's per-argument exec() limit (MAX_ARG_STRLEN, ~128KB) once a
    # shard selects a few thousand tests, which fails with "Argument list
    # too long" (observed with CompilerBackendTests: 9000+ tests total).
    # `swift test --filter` may be repeated any number of times (patterns
    # are OR'd), so chunk the alternation into many small arguments instead
    # of one huge one.
    chunk_size=100
    declare -a filter_args=()
    chunk_regex=""
    chunk_len=0
    for t in "${shard_tests[@]}"; do
        esc="$(printf '%s' "$t" | sed -e 's/\./\\./g')"
        if (( chunk_len == 0 )); then
            chunk_regex="$esc"
        else
            chunk_regex+="|$esc"
        fi
        chunk_len=$(( chunk_len + 1 ))
        if (( chunk_len >= chunk_size )); then
            filter_args+=(--filter "^(${chunk_regex})\$")
            chunk_regex=""
            chunk_len=0
        fi
    done
    if (( chunk_len > 0 )); then
        filter_args+=(--filter "^(${chunk_regex})\$")
    fi

    echo "shard_swift_tests.sh: split into $(( ${#filter_args[@]} / 2 )) --filter chunks of up to $chunk_size tests each." >&2

    run_filter_chunks "${filter_args[@]}"
    exit $?
fi

# ---------------------------------------------------------------------------
# Mode: static — shard at the suite/class level via source grepping.
# ---------------------------------------------------------------------------
echo "shard_swift_tests.sh: extracting suite/class names from '$tests_dir'..." >&2
mapfile -t all_types < <(
    find "$tests_dir" -name '*.swift' -print0 \
        | xargs -0 awk '
            function emit_decl(line, decl, parts, count) {
                if (match(line, /(^|[[:space:]])((final|private|fileprivate|internal|public|open)[[:space:]]+)*(struct|class)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
                    decl = substr(line, RSTART, RLENGTH)
                    count = split(decl, parts, /[[:space:]]+/)
                    print parts[count]
                    return 1
                }
                return 0
            }

            FNR == 1 {
                pending_suite = 0
            }

            /@Suite/ {
                if (emit_decl($0)) {
                    pending_suite = 0
                    next
                }
                pending_suite = 1
                next
            }

            $0 ~ /(^|[[:space:]])((final|private|fileprivate|internal|public|open)[[:space:]]+)*class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[^{:]*:[^{]*XCTestCase/ {
                emit_decl($0)
                pending_suite = 0
                next
            }

            pending_suite && emit_decl($0) {
                pending_suite = 0
                next
            }

            pending_suite && $0 !~ /^[[:space:]]*(@|\/\/|$)/ {
                pending_suite = 0
            }
        ' \
        | sort -u
)

total="${#all_types[@]}"
echo "shard_swift_tests.sh: found $total candidate suite/class names." >&2

declare -a own_types=()
for (( i = 0; i < total; i++ )); do
    if (( i % shard_count == shard_index )); then
        own_types+=("${all_types[$i]}")
    fi
done

echo "shard_swift_tests.sh: shard $shard_index/$shard_count owns ${#own_types[@]} of $total suite/class names." >&2

declare -a filters=()

if (( shard_index == shard_count - 1 && total == 0 )); then
    # Extraction found nothing at all; fall back to running everything under
    # this prefix on the last shard so no test target is silently lost.
    filters+=("^${target_prefix}\\.")
fi

if (( ${#own_types[@]} == 0 && ${#filters[@]} == 0 )); then
    echo "shard_swift_tests.sh: shard $shard_index has no assigned suites and is not the catch-all shard; skipping." >&2
    exit 0
fi

declare -a filter_args=()
if (( ${#own_types[@]} > 0 )); then
    chunk_size=50
    chunk_regex=""
    chunk_len=0
    for t in "${own_types[@]}"; do
        if (( chunk_len == 0 )); then
            chunk_regex="$t"
        else
            chunk_regex+="|$t"
        fi
        chunk_len=$(( chunk_len + 1 ))
        if (( chunk_len >= chunk_size )); then
            filter_args+=(--filter "^${target_prefix}\\.(${chunk_regex})(/|\$)")
            chunk_regex=""
            chunk_len=0
        fi
    done
    if (( chunk_len > 0 )); then
        filter_args+=(--filter "^${target_prefix}\\.(${chunk_regex})(/|\$)")
    fi

    echo "shard_swift_tests.sh: split suite/class filter into $(( ${#filter_args[@]} / 2 )) chunks of up to $chunk_size names each." >&2
fi

for f in "${filters[@]}"; do
    filter_args+=(--filter "$f")
done

run_filter_chunks "${filter_args[@]}"
exit $?
