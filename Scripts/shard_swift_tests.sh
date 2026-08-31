#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<'USAGE'
Usage:
  shard_swift_tests.sh --mode dynamic --list-filter <regex> \
      [--list-exclude <regex>] \
      [--target-prefix <SwiftPM-test-product>] \
      --shard-index N --shard-count N [-- swift_test.sh-args...]

  shard_swift_tests.sh --mode static --tests-dir <path> --target-prefix <Module> \
      --shard-index N --shard-count N [-- swift_test.sh-args...]

Splits a full-swift-tests matrix entry into --shard-count interleaved shards
and runs Scripts/swift_test.sh with a --filter that selects only this
shard's share, so multiple CI jobs can split one slow test target.

Modes:
  dynamic   Lists concrete test identifiers via `swift test list --skip-build`
            (requires the target to already be built), filters the documented
            specifier list, and shards at the individual-test level. Supports
            both XCTest and Swift Testing identifiers.

  static    Extracts test suite type names by scanning test sources under
            --tests-dir for XCTestCase classes and Swift Testing @Suite
            declarations, estimates each suite's test weight from source
            declarations, and greedily balances the weighted suites across
            shards. Each shard's --filter selects
            `^<prefix>\.(Type1|Type2|...)(/|$)`. If extraction finds no
            candidates at all, the last shard falls back to running the full
            target prefix so a misconfigured path does not silently skip the
            entire target.

Options:
  --mode <dynamic|static>   Sharding mode (required)
  --list-filter <regex>     (dynamic) regex applied locally to `swift test list`
  --list-exclude <regex>    (dynamic) optional regex removed from the matched
                             test list before sharding
  --tests-dir <path>        (static) directory to grep test sources from
  --target-prefix <name>    (static) module prefix for the --filter regex;
                             (dynamic) optional swiftbuild test product
  --shard-index <n>         0-based shard index (default: 0)
  --shard-count <n>         Total shard count (default: 1 = no CI-level
                             sharding; the full matched set still runs
                             through this shard, chunked into --filter
                             batches to stay under exec() argument limits)
  -h, --help                Show this help

Remaining args (after `--`, or any unrecognized args) are forwarded to
Scripts/swift_test.sh, e.g. -Xswiftc flags. --skip-build is always added.
USAGE
}

mode=""
list_filter=""
list_exclude=""
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
        --list-exclude)
            list_exclude="$2"; shift 2 ;;
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
    # swiftbuild creates per-test-target products; `swift test` needs to know
    # which product to load. The target_prefix is the product name.
    if (( use_swiftbuild_product )); then
        SWIFT_TEST_PRODUCT="$target_prefix" bash "$SCRIPT_DIR/swift_test.sh" --skip-build "$@" "${passthrough[@]}"
    else
        bash "$SCRIPT_DIR/swift_test.sh" --skip-build "$@" "${passthrough[@]}"
    fi
}

run_filter_chunks() {
    local total=$(( $# / 2 ))
    local chunk=1
    local flag pattern

    while (( $# > 0 )); do
        flag="$1"
        pattern="$2"
        shift 2

        # SwiftPM 6.2 does not reliably combine repeated --filter flags,
        # so each chunk must run as its own swift test invocation.
        echo "shard_swift_tests.sh: running filter chunk ${chunk}/${total}." >&2
        run_swift_test "$flag" "$pattern" || return $?
        chunk=$(( chunk + 1 ))
    done

    return 0
}

# Appends --filter args for each alternation chunk read from stdin, wrapped as
# "${prefix}(chunk)${suffix}", into the caller-named array.
append_filter_chunks() {
    local prefix="$1" suffix="$2"
    local -n __out="$3"
    local chunk
    while IFS= read -r chunk; do
        __out+=(--filter "${prefix}(${chunk})${suffix}")
    done
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

# shard_count defaults to 1 (no CI-level sharding), but every mode below
# still lists tests and chunks the --filter regex. Dynamic mode uses
# shard_interleave over individual test identifiers; static mode uses a
# weighted greedy assignment over suite/class names. A lone shard therefore
# still runs all chunks in sequence. Skipping straight to a single raw
# --filter would reintroduce the "Argument list too long" exec() failure this
# chunking exists to avoid once a shard's matched-test set gets large
# (observed with RuntimeTests under --no-parallel: a serialized target invokes
# the whole matched list as one process argument, unlike --parallel which fans
# it out across workers).

# ---------------------------------------------------------------------------
# Enable swiftbuild's integrated compilation cache if requested.
kswiftk_setup_compile_cache_env

# Select the same build system used by build_swift_tests.sh.
build_system_arg=()
if [[ -n "${SWIFT_BUILD_SYSTEM:-}" ]]; then
    build_system_arg=(--build-system "${SWIFT_BUILD_SYSTEM}")
fi

# swiftbuild creates per-test-target products, so both `swift test list` and
# `swift test` need to be told which product to load.
use_swiftbuild_product=0
if [[ -n "${target_prefix:-}" && "${SWIFT_BUILD_SYSTEM:-}" == "swiftbuild" ]]; then
    use_swiftbuild_product=1
fi

list_product_arg=()
if (( use_swiftbuild_product )); then
    list_product_arg=(--test-product "$target_prefix")
fi

# Mode: dynamic — shard at the individual-test level via `swift test list`.
# ---------------------------------------------------------------------------
if [[ "$mode" == "dynamic" ]]; then
    echo "shard_swift_tests.sh: listing tests matching '$list_filter'..." >&2
    if [[ -n "$list_exclude" ]]; then
        echo "shard_swift_tests.sh: excluding tests matching '$list_exclude'." >&2
    fi
    # `swift test list` does not honor --filter on every SwiftPM version.
    # List everything and apply the requested shard prefix locally.
    test_list=""
    if ! test_list="$(
        swift test list --skip-build "${list_product_arg[@]}" "${build_system_arg[@]}" \
            | awk -v filter="$list_filter" -v exclude="$list_exclude" \
                '$0 ~ filter && (exclude == "" || $0 !~ exclude) { print }' \
            | sort
    )"; then
        echo "shard_swift_tests.sh: test discovery failed." >&2
        exit 1
    fi

    declare -a all_tests=()
    if [[ -n "$test_list" ]]; then
        mapfile -t all_tests <<< "$test_list"
    fi

    total="${#all_tests[@]}"
    if (( total == 0 )); then
        echo "shard_swift_tests.sh: no tests matched '$list_filter'; nothing to run." >&2
        exit 0
    fi

    mapfile -t shard_tests < <(
        printf '%s\n' "${all_tests[@]}" | shard_interleave "$shard_index" "$shard_count"
    )

    echo "shard_swift_tests.sh: shard $shard_index/$shard_count selects ${#shard_tests[@]} of $total tests." >&2

    if (( ${#shard_tests[@]} == 0 )); then
        echo "shard_swift_tests.sh: shard $shard_index has no tests; skipping." >&2
        exit 0
    fi

    # Escape every regex metacharacter in the documented test specifier. Swift
    # Testing identifiers include parameter labels and parentheses, while
    # XCTest identifiers are usually limited to "Module.Class/method".
    #
    # A single --filter regex alternating every selected test can exceed
    # Linux's per-argument exec() limit (MAX_ARG_STRLEN, ~128KB) once a
    # shard selects a few thousand tests, which fails with "Argument list
    # too long" (observed with CompilerBackendTests: 9000+ tests total).
    # SwiftPM 6.2 does not reliably OR repeated --filter flags, so chunk the
    # alternation across multiple invocations instead of one huge argument.
    chunk_size=400
    declare -a filter_args=()
    # Swift Testing may append a runtime case path after the identifier
    # printed by `swift test list`; XCTest ends at the listed identifier.
    append_filter_chunks "^" "(/|\$)" filter_args < <(
        printf '%s\n' "${shard_tests[@]}" \
            | sed -e 's/[][\\.^$*+?(){}|]/\\&/g' \
            | chunk_alternations "$chunk_size"
    )

    echo "shard_swift_tests.sh: split into $(( ${#filter_args[@]} / 2 )) --filter chunks of up to $chunk_size tests each." >&2

    run_filter_chunks "${filter_args[@]}"
    exit $?
fi

# ---------------------------------------------------------------------------
# Mode: static — shard at the suite/class level via source grepping.
# ---------------------------------------------------------------------------
echo "shard_swift_tests.sh: extracting suite/class names from '$tests_dir'..." >&2
mapfile -t all_type_records < <(
    find "$tests_dir" -name '*.swift' -print0 \
        | xargs -0 awk '
            function emit_decl(line, decl, parts, count) {
                if (match(line, /(^|[[:space:]])((final|private|fileprivate|internal|public|open)[[:space:]]+)*(struct|class)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
                    decl = substr(line, RSTART, RLENGTH)
                    count = split(decl, parts, /[[:space:]]+/)
                    return parts[count]
                }
                return ""
            }

            function emit_extension(line, extension_decl) {
                if (match(line, /extension[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
                    extension_decl = substr(line, RSTART, RLENGTH)
                    sub(/^extension[[:space:]]+/, "", extension_decl)
                    return extension_decl
                }
                return ""
            }

            function register_candidate(name) {
                if (name == "") {
                    return
                }
                candidates[name] = 1
                current_type = name
                pending_suite = 0
                pending_test = 0
            }

            function register_observed(name) {
                if (name != "") {
                    current_type = name
                    pending_test = 0
                }
            }

            FNR == 1 {
                current_type = ""
                pending_suite = 0
                pending_test = 0
            }

            {
                line = $0

                if (line ~ /@Suite/) {
                    suite_name = emit_decl(line)
                    if (suite_name != "") {
                        register_candidate(suite_name)
                        next
                    }
                    pending_suite = 1
                    next
                }

                suite_name = emit_decl(line)
                if (pending_suite && suite_name != "") {
                    register_candidate(suite_name)
                    next
                }

                if (line ~ /(^|[[:space:]])((final|private|fileprivate|internal|public|open)[[:space:]]+)*class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[^{:]*:[^{]*XCTestCase/) {
                    register_candidate(suite_name)
                    next
                }

                extension_name = emit_extension(line)
                if (extension_name != "") {
                    register_observed(extension_name)
                    next
                }

                if (pending_suite && line !~ /^[[:space:]]*(@|\/\/|$)/) {
                    pending_suite = 0
                }

                if (current_type != "") {
                    if (line ~ /@Test([[:space:]]|\(|$)/) {
                        weights[current_type]++
                        pending_test = (line ~ /func[[:space:]]+test[A-Za-z0-9_]*/) ? 0 : 1
                    } else if (line ~ /func[[:space:]]+test[A-Za-z0-9_]*/) {
                        if (!pending_test) {
                            weights[current_type]++
                        }
                        pending_test = 0
                    } else if (pending_test && line !~ /^[[:space:]]*(@|\/\/|$)/) {
                        pending_test = 0
                    }
                }
            }

            END {
                for (name in candidates) {
                    # Keep every suite visible to the sharder, including
                    # suites whose source declaration has no explicit test
                    # marker in the scanned file.
                    printf "%s\t%d\n", name, weights[name] + 1
                }
            }
        ' \
        | sort -t $'\t' -k1,1
)

declare -A type_weights=()
total_weight=0
for record in "${all_type_records[@]}"; do
    IFS=$'\t' read -r type weight <<< "$record"
    type_weights["$type"]="$weight"
    total_weight=$(( total_weight + weight ))
done

total="${#all_type_records[@]}"
echo "shard_swift_tests.sh: found $total candidate suite/class names with estimated test weight $total_weight." >&2

declare -a own_types=()
if (( total > 0 )); then
    mapfile -t own_types < <(
        printf '%s\n' "${all_type_records[@]}" \
            | sort -t $'\t' -k2,2nr -k1,1 \
            | awk -F '\t' -v requested_index="$shard_index" -v shard_total="$shard_count" '
                BEGIN {
                    for (i = 0; i < shard_total; i++) {
                        loads[i] = 0
                    }
                }
                {
                    target = 0
                    for (i = 1; i < shard_total; i++) {
                        if (loads[i] < loads[target]) {
                            target = i
                        }
                    }
                    loads[target] += $2
                    if (target == requested_index) {
                        print $1
                    }
                }
            ' \
            | sort
    )
fi

own_weight=0
for type in "${own_types[@]}"; do
    own_weight=$(( own_weight + type_weights["$type"] ))
done

echo "shard_swift_tests.sh: shard $shard_index/$shard_count owns ${#own_types[@]} of $total suite/class names (estimated test weight $own_weight/$total_weight)." >&2

catch_all=0
if (( shard_index == shard_count - 1 && total == 0 )); then
    catch_all=1
fi

if (( ${#own_types[@]} == 0 && ! catch_all )); then
    echo "shard_swift_tests.sh: shard $shard_index has no assigned suites and is not the catch-all shard; skipping." >&2
    exit 0
fi

declare -a filter_args=()
if (( ${#own_types[@]} > 0 )); then
    # Serialized runs (--no-parallel) exec the whole matched test-identifier
    # list as a single process argument, so their suite chunks must stay far
    # below Linux MAX_ARG_STRLEN once expanded to concrete test IDs. Parallel
    # runs fan matched tests out across workers and only carry the suite-name
    # alternation inside the one --filter argument (~40 bytes per name), so a
    # much larger chunk keeps a shard in a single swift test invocation and
    # avoids draining worker parallelism at every serial chunk boundary.
    if [[ "${SWIFT_TEST_PARALLEL:-}" == "0" || "${SWIFT_TEST_PARALLEL:-}" == "false" ]]; then
        chunk_size=50
    else
        chunk_size=300
    fi
    append_filter_chunks "^${target_prefix}\\." "(/|\$)" filter_args < <(
        printf '%s\n' "${own_types[@]}" | chunk_alternations "$chunk_size"
    )

    echo "shard_swift_tests.sh: split suite/class filter into $(( ${#filter_args[@]} / 2 )) chunks of up to $chunk_size names each." >&2
fi

if (( catch_all )); then
    # Extraction found nothing at all; fall back to running everything under
    # this prefix on the last shard so no test target is silently lost.
    filter_args+=(--filter "^${target_prefix}\\.")
fi

run_filter_chunks "${filter_args[@]}"
exit $?
