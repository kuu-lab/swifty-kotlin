#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

echo "build_swift_tests.sh: strict-building source and test targets." >&2
# SwiftPM does not allow `--target` and `--build-tests` together, and test
# targets cannot be selected by `--target` alone. Build the complete test graph
# in one invocation so this wrapper remains valid as test targets are added or
# renamed in Package.swift.
swift build --build-tests "$@"

echo "build_swift_tests.sh: building SwiftPM test runner with generated-code warnings suppressed." >&2
swift build --build-tests "$@" -Xswiftc -suppress-warnings
