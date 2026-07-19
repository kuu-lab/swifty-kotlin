#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

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
# (LSPServerTests's dependency closura: CompilerCore/CompilerBackend/Runtime/
# RuntimeABI/LSPServer) paid for a full rebuild in the second pass anyway.
# One warnings-visible build-tests call is strictly more correct and faster.
echo "build_swift_tests.sh: building source and test targets." >&2
swift build --build-tests "$@"
