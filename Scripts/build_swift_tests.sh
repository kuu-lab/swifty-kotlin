#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Detect the swift-driver warning that silently turns compilation caching back
# off (seen when -cache-compile-job is passed without -explicit-module-build).
# Caching silently degrading to a full rebuild burned ~11 CI minutes per job
# before this guard existed, so a successful build that dropped caching must
# be treated as a failure.
kswiftk_compile_cache_was_dropped() {
    local build_log="$1"
    [[ "${SWIFT_ENABLE_COMPILE_CACHE:-}" == "1" ]] && grep -q "turn off caching" "$build_log"
}

# Retry `swift build` a few times on intermittent crashes observed with the
# Swift 6.3+ swiftbuild backend on Linux (SIGSEGV/SIGBUS/SIGILL). Normal
# compile errors are not retried.
kswiftk_build_with_retry() {
    local max_attempts=3
    local build_log="${TMPDIR:-/tmp}/kswiftk_build_swift_tests_$$.log"
    local attempt
    trap 'rm -f "$build_log"' RETURN

    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        local exit_code=0
        if [[ "${SWIFT_ENABLE_COMPILE_CACHE:-}" == "1" ]]; then
            # Only capture output to a file when something will read it back.
            swift build "$@" 2>&1 | tee "$build_log" || exit_code=$?
        else
            swift build "$@" || exit_code=$?
        fi

        if [[ $exit_code -eq 0 ]]; then
            if kswiftk_compile_cache_was_dropped "$build_log"; then
                echo "build_swift_tests.sh: SWIFT_ENABLE_COMPILE_CACHE=1 but swift-driver disabled compilation caching (see 'turn off caching' warning above)." >&2
                return 1
            fi
            return 0
        fi

        if [[ $exit_code != 132 && $exit_code != 138 && $exit_code != 139 ]]; then
            return $exit_code
        fi
        if [[ $attempt -ge $max_attempts ]]; then
            echo "build_swift_tests.sh: swift build failed after $attempt attempt(s) (exit $exit_code)" >&2
            return $exit_code
        fi
        echo "build_swift_tests.sh: swift build crashed with signal $exit_code on attempt $attempt; retrying..." >&2
    done
}

# `swift build --build-tests` builds every test target plus its full
# dependency closure in one pass. SwiftPM's `--target` flag is NOT cumulative
# (only the last `--target` in a command is actually built; earlier ones are
# silently skipped), so building multiple targets requires one
# `swift build --target <T>` invocation per target, in a loop, each with
# identical flags so SwiftPM's incremental cache stays valid across the loop.
#
# When SWIFT_TEST_BUILD_TARGETS is set, build only those targets (one
# invocation per target) so CI lanes can build the minimal set they need.
# With the Swift 6.3+ `swiftbuild` build system, per-target test products are
# named `<Target>-test-runner`; select the build system via SWIFT_BUILD_SYSTEM
# (default: native).
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
kswiftk_append_build_system_flag swift_build_args

# Enable swiftbuild's integrated compilation cache if requested.
kswiftk_setup_compile_cache_env

# Append compilation-caching flags if requested. This must match the flags used
# by any later `swift test --skip-build` invocation so the incremental cache is
# not invalidated.
kswiftk_append_compile_cache_flags swift_build_args

if [[ -z "$build_targets" || "$build_system" == "native" ]]; then
    # The legacy native build system produces a single PackageTests bundle.
    # We must build all test targets together with --build-tests so that
    # subsequent `swift test --skip-build` invocations can find the bundle.
    echo "build_swift_tests.sh: building source and all test targets." >&2
    kswiftk_build_with_retry --build-tests "${swift_build_args[@]}"
else
    echo "build_swift_tests.sh: building selected test targets: $build_targets" >&2
    # swiftbuild creates per-test-target products as `<Target>-test-runner`.
    target_suffix=""
    [[ "$build_system" == "swiftbuild" ]] && target_suffix="-test-runner"
    for target in $build_targets; do
        echo "build_swift_tests.sh: building --target ${target}${target_suffix}" >&2
        kswiftk_build_with_retry --target "${target}${target_suffix}" "${swift_build_args[@]}"
    done
fi
