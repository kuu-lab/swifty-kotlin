#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Retry `swift build` a few times on intermittent crashes observed with the
# Swift 6.3+ swiftbuild backend on Linux (SIGSEGV/SIGBUS/SIGILL). Normal
# compile errors are not retried.
kswiftk_build_with_retry() {
    local max_attempts=3
    local attempt=0
    while true; do
        attempt=$((attempt + 1))
        swift build "$@" && return 0
        local exit_code=$?
        if [[ $attempt -ge $max_attempts ]]; then
            echo "build_swift_tests.sh: swift build failed after $attempt attempt(s) (exit $exit_code)" >&2
            return $exit_code
        fi
        case $exit_code in
            132|138|139)
                echo "build_swift_tests.sh: swift build crashed with signal $exit_code on attempt $attempt; retrying..." >&2
                ;;
            *)
                return $exit_code
                ;;
        esac
    done
}

# A single `swift build --build-tests` already builds every test target
# (CompilerCoreTests, CompilerBackendTests, RuntimeTests, RuntimeTestsParallel,
# KSwiftKCLITests, LSPServerTests) plus everything they depend on - it's the
# same dependency closure a prior two-pass version of this script tried to
# warm separately via `--target CompilerCoreTests --target ... --target
# LSPServerTests` before this build-tests call. That repeated-`--target`
# pass never did what it looked like it did: SwiftPM's `--target` flag isn't
# cumulative, so only the last `--target` in the list (LSPServerTests) was
# ever actually built (confirmed locally: `swift build --target A --target B`
# only produces B's output - A is silently skipped, no warning/error). Worse,
# because that pass's flags differed from this one's (it added
# -Xswiftc -suppress-warnings here but not there), the flag mismatch
# invalidated SwiftPM's incremental build cache and forced this call to
# recompile everything the first pass *did* build, from scratch (repro'd
# locally with --build-system native, the engine CI's ubuntu-latest runners
# use). Net effect of the old two-pass design: 5 of 6 test targets never got
# warning coverage from the first pass at all, and the targets that did
# (LSPServerTests's dependency closure: CompilerCore/CompilerBackend/Runtime/
# RuntimeABI/LSPServer) paid for a full rebuild in the second pass anyway.
#
# When SWIFT_TEST_BUILD_TARGETS is set, build only those targets one at a time
# so multiple CI lanes can each build the minimal set they need. Because
# SwiftPM's `--target` is not cumulative, multiple targets must be built in a
# loop with one `swift build --target <T>` invocation per target. Every
# invocation receives the same command-line flags (and the same cache flags,
# when compilation caching is enabled) so SwiftPM can reuse already-built
# artifacts across the loop and across the subsequent `swift test --skip-build`.
#
# With the Swift 6.3+ `swiftbuild` build system, per-test-target products are
# named `<Target>-test-runner` (e.g. `CompilerCoreTests-test-runner`). The
# build system can be selected via SWIFT_BUILD_SYSTEM (default: native).
build_targets="${SWIFT_TEST_BUILD_TARGETS:-}"
build_system="${SWIFT_BUILD_SYSTEM:-}"

declare -a swift_build_args=("$@")

# Optional CI-only speed knobs. These are intentionally opt-in via an env var
# so local developer builds keep debug info by default. Note:
# --disable-index-store cannot be combined with swift build --build-tests on
# Linux because XCTest test discovery reads the index store; disabling it
# causes "error: index store path does not exist" for the discovered-tests
# target. -debug-info-format none is safe and reduces object file size/I/O.
if [[ "${KSWIFTK_CI_FAST_BUILD:-}" == "1" ]]; then
    echo "build_swift_tests.sh: enabling fast build flags." >&2
    swift_build_args+=(-debug-info-format none)
fi

# Make sure any selected build system is applied to every invocation.
if [[ -n "$build_system" ]]; then
    swift_build_args+=(--build-system "$build_system")
fi

# Enable swiftbuild's integrated compilation cache if requested.
kswiftk_setup_compile_cache_env

# Append compilation-caching flags if requested. This must match the flags used
# by any later `swift test --skip-build` invocation so the incremental cache is
# not invalidated.
kswiftk_append_compile_cache_flags swift_build_args

if [[ -z "$build_targets" ]]; then
    echo "build_swift_tests.sh: building source and all test targets." >&2
    kswiftk_build_with_retry --build-tests "${swift_build_args[@]}"
else
    echo "build_swift_tests.sh: building selected test targets: $build_targets" >&2
    for target in $build_targets; do
        # swiftbuild creates per-test-target products as `<Target>-test-runner`.
        if [[ "$build_system" == "swiftbuild" ]]; then
            target="${target}-test-runner"
        fi
        echo "build_swift_tests.sh: building --target $target" >&2
        kswiftk_build_with_retry --target "$target" "${swift_build_args[@]}"
    done
fi
