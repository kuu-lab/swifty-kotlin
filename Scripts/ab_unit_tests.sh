#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<'USAGE'
Usage:
  ab_unit_tests.sh --build-config debug|release \
      [--optimize-compiler-core] [--workers N] [--output <tsv-path>]

A/B helper that builds the full test suite once and then runs the unit-test
groups used by the CI (CompilerCore, CompilerBackend, Runtime, RuntimeParallel,
KSwiftKCLI, LSPServer) while recording per-phase wall-clock seconds to a TSV.

Options:
  --build-config debug|release  Build configuration passed to swift test/build.
  --optimize-compiler-core      Set KSWIFTK_OPTIMIZE_COMPILER_CORE=1 so that
                                Package.swift emits -O for CompilerCore in debug.
  --workers N                   Build jobs / parallel test workers (default: detected).
  --output <tsv-path>           Metrics output path (default: $RUNNER_TEMP/ab_unit_tests_metrics.tsv).
  -h, --help                    Show this help.
USAGE
}

build_config="debug"
optimize_compiler_core=false
workers=""
output=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-config)
            build_config="$2"
            shift 2
            ;;
        --optimize-compiler-core)
            optimize_compiler_core=true
            shift
            ;;
        --workers)
            workers="$2"
            shift 2
            ;;
        --output)
            output="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ab_unit_tests.sh: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "$build_config" != "debug" && "$build_config" != "release" ]]; then
    echo "ab_unit_tests.sh: --build-config must be 'debug' or 'release' (got '$build_config')" >&2
    exit 1
fi

if [[ "$optimize_compiler_core" == true ]]; then
    export KSWIFTK_OPTIMIZE_COMPILER_CORE=1
fi

if [[ -z "$workers" ]]; then
    workers="$(detect_workers)"
fi
if [[ -z "$workers" || "$workers" -le 0 ]]; then
    workers=1
fi

metrics_file="${output:-${RUNNER_TEMP:-/tmp}/ab_unit_tests_metrics.tsv}"
touch "$metrics_file"

record_metric() {
    printf '%s\t%s\n' "$1" "$2" >> "$metrics_file"
}

strict_flags=(-Xswiftc -swift-version -Xswiftc 6 -Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency -Xswiftc -enable-testing)

declare -a build_args=(-j "$workers" "${strict_flags[@]}")
if [[ "$build_config" == "release" ]]; then
    build_args+=(-c release)
fi

declare -a test_args=("${strict_flags[@]}")
if [[ "$build_config" == "release" ]]; then
    test_args+=(-c release)
fi

# Exported so swift_test.sh and shard_swift_tests.sh pick them up by default.
export SWIFT_TEST_WORKERS="$workers"
export SWIFT_TEST_BUILD_JOBS="$workers"

run_test_group() {
    local name="$1"
    local parallel_mode="$2"
    shift 2
    local start=$SECONDS
    echo "ab_unit_tests.sh: running test group '$name'..." >&2
    if [[ -n "$parallel_mode" ]]; then
        SWIFT_TEST_PARALLEL="$parallel_mode" "$@"
    else
        "$@"
    fi
    record_metric "$name" "$((SECONDS - start))"
}

build_start=$SECONDS
bash "$SCRIPT_DIR/build_swift_tests.sh" "${build_args[@]}"
record_metric "build" "$((SECONDS - build_start))"

# CompilerCore tests except the parallel benchmark suite.
run_test_group "compiler_core" "" \
    bash "$SCRIPT_DIR/shard_swift_tests.sh" \
        --mode static --tests-dir Tests/CompilerCoreTests --target-prefix CompilerCoreTests \
        --shard-index 0 --shard-count 1 \
        -- --skip '^CompilerCoreTests\.FrontendParallelBenchmarkTests/' "${test_args[@]}"

# Frontend parallel benchmarks are run serially to avoid worker contention.
run_test_group "frontend_benchmark" "0" \
    bash "$SCRIPT_DIR/swift_test.sh" --skip-build --filter '^CompilerCoreTests\.FrontendParallelBenchmarkTests/' "${test_args[@]}"

run_test_group "compiler_backend" "" \
    bash "$SCRIPT_DIR/shard_swift_tests.sh" \
        --mode static --tests-dir Tests/CompilerBackendTests --target-prefix CompilerBackendTests \
        --shard-index 0 --shard-count 1 \
        -- "${test_args[@]}"

run_test_group "runtime" "0" \
    bash "$SCRIPT_DIR/shard_swift_tests.sh" \
        --mode static --tests-dir Tests/RuntimeTests --target-prefix RuntimeTests \
        --shard-index 0 --shard-count 1 \
        -- "${test_args[@]}"

run_test_group "runtime_parallel" "1" \
    bash "$SCRIPT_DIR/swift_test.sh" --skip-build --filter '^RuntimeTestsParallel\.' "${test_args[@]}"

run_test_group "kswiftk_cli" "1" \
    bash "$SCRIPT_DIR/swift_test.sh" --skip-build --filter '^KSwiftKCLITests\.' "${test_args[@]}"

run_test_group "lsp" "1" \
    bash "$SCRIPT_DIR/swift_test.sh" --skip-build --filter '^LSPServerTests\.' "${test_args[@]}"

total=0
while IFS=$'\t' read -r key value; do
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        total=$((total + value))
    fi
done < "$metrics_file"
record_metric "total" "$total"

echo "ab_unit_tests.sh: metrics written to $metrics_file" >&2
cat "$metrics_file" >&2
