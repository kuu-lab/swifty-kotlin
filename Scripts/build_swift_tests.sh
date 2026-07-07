#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

declare -a test_targets=(
    CompilerCoreTests
    CompilerBackendTests
    RuntimeTests
    RuntimeTestsParallel
    KSwiftKCLITests
    LSPServerTests
)

declare -a target_args=()
for target in "${test_targets[@]}"; do
    target_args+=(--target "$target")
done

echo "build_swift_tests.sh: strict-building source and test targets." >&2
swift build "${target_args[@]}" "$@"

echo "build_swift_tests.sh: building SwiftPM test runner with generated-code warnings suppressed." >&2
swift build --build-tests "$@" -Xswiftc -suppress-warnings
