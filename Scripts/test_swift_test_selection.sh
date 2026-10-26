#!/usr/bin/env bash
# Exercise filtering and product selection without building a Swift package.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-test-selection.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/repo/Scripts/lib" "$TEST_DIR/repo/Tests/CompilerCoreTests" "$TEST_DIR/bin"
cp "$SCRIPT_DIR/swift_test.sh" "$SCRIPT_DIR/swift_build.sh" "$TEST_DIR/repo/Scripts/"
cp "$SCRIPT_DIR/lib/common.sh" "$SCRIPT_DIR/lib/check_swift_test_filter.py" \
    "$SCRIPT_DIR/lib/swift_build_slots.py" "$TEST_DIR/repo/Scripts/lib/"
cat > "$TEST_DIR/repo/Tests/CompilerCoreTests/Example.swift" <<'EOF'
@Suite struct WrongSuite {
    let misleading = "func targetTest() { }"
    /* func targetTest() {} */
}
@Suite struct RightSuite {
    @Test func targetTest() { let text = #"{ hello }"# }
}
extension RightSuite {
    @Test func anotherTest() {}
}
EOF
cat > "$TEST_DIR/bin/swift" <<'EOF'
#!/usr/bin/env bash
if [[ "${2:-}" == --help-hidden ]]; then
    printf '%s\n' '--build-system <build-system>' '    (default: swiftbuild)'
    exit 0
fi
printf '%s\n' "$@" > "$SWIFT_ARGS_LOG"
if [[ "${FAKE_NO_MATCH:-}" == 1 || "${FAKE_NO_MATCH:-}" == mixed ]]; then
    echo 'warning: No matching test cases were run'
fi
if [[ "${FAKE_NO_MATCH:-}" == zero ]]; then
    echo 'Test run with 0 tests in 0 suites passed'
elif [[ "${FAKE_NO_MATCH:-}" != 1 ]]; then
    echo 'Build complete! (0.01s)'
    echo 'Test run with 1 test in 1 suite passed'
fi
EOF
cat > "$TEST_DIR/bin/nproc" <<'EOF'
#!/usr/bin/env bash
echo 8
EOF
cat > "$TEST_DIR/bin/uname" <<'EOF'
#!/usr/bin/env bash
echo Linux
EOF
chmod +x "$TEST_DIR/bin/"*
wrapper="$TEST_DIR/repo/Scripts/swift_test.sh"

run_wrapper() {
    rm -f "$TEST_DIR/args"
    env -u SWIFT_TEST_PRODUCT -u SWIFT_BUILD_SYSTEM -u SWIFT_TEST_BUILD_JOBS -u SWIFT_BUILD_JOBS \
        -u SWIFT_TEST_SOURCE_PREFLIGHT -u GITHUB_ACTIONS -u CI -u FAKE_NO_MATCH \
        PATH="$TEST_DIR/bin:$PATH" SWIFT_ARGS_LOG="$TEST_DIR/args" \
        SWIFT_BUILD_SLOT_DIR="$TEST_DIR/slots" SWIFT_BUILD_SLOTS=0 \
        "$@" > "$TEST_DIR/output" 2>&1
}
expect_line() {
    if ! grep -qxF -- "$1" "$2"; then
        cat "$TEST_DIR/output" >&2
        echo "FAIL: expected $1 in $2" >&2
        exit 1
    fi
}
reject_line() {
    if grep -qxF -- "$1" "$2"; then
        cat "$TEST_DIR/output" >&2
        echo "FAIL: unexpected $1 in $2" >&2
        exit 1
    fi
}

# A fully qualified but misassociated suite/method is rejected before SwiftPM.
if run_wrapper bash "$wrapper" --filter 'CompilerCoreTests.WrongSuite/targetTest'; then
    echo 'FAIL: accepted a method belonging to another suite' >&2; exit 1
fi
[[ ! -e "$TEST_DIR/args" ]] || { echo 'FAIL: preflight started SwiftPM' >&2; exit 1; }
grep -qF 'no matching test in that suite' "$TEST_DIR/output"
if run_wrapper bash "$wrapper" --filter 'CompilerCoreTests.MissingSuite'; then
    echo 'FAIL: accepted an unknown suite' >&2; exit 1
fi
[[ ! -e "$TEST_DIR/args" ]] || { echo 'FAIL: missing-suite preflight started SwiftPM' >&2; exit 1; }
grep -qF 'no matching suite found' "$TEST_DIR/output"

# The normal and extension declarations pass; an anchored literal module
# prefix picks the corresponding product when swiftbuild is selected.
run_wrapper bash "$wrapper" --filter '^CompilerCoreTests\.RightSuite/targetTest'
expect_line --test-product "$TEST_DIR/args"
expect_line CompilerCoreTests "$TEST_DIR/args"
run_wrapper SWIFT_BUILD_SYSTEM=swiftbuild bash "$wrapper" --filter '^CompilerCoreTests\.RightSuite'
expect_line --test-product "$TEST_DIR/args"
run_wrapper SWIFT_BUILD_SYSTEM=swiftbuild bash "$wrapper" --filter=CompilerCoreTests.RightSuite/anotherTest
reject_line --test-product "$TEST_DIR/args"  # Unanchored regex is not narrowed.

# Native builds, alternation, an optional separator and prebuilt bundles must
# not be silently narrowed; explicit product selection remains authoritative.
run_wrapper SWIFT_BUILD_SYSTEM=native bash "$wrapper" --filter '^CompilerCoreTests\.RightSuite/targetTest'
reject_line --test-product "$TEST_DIR/args"
run_wrapper SWIFT_BUILD_SYSTEM=swiftbuild bash "$wrapper" --filter '^CompilerCoreTests\.RightSuite|OtherTests\.Suite'
reject_line --test-product "$TEST_DIR/args"
run_wrapper SWIFT_BUILD_SYSTEM=swiftbuild bash "$wrapper" --filter '^CompilerCoreTests\.?RightSuite'
reject_line --test-product "$TEST_DIR/args"
run_wrapper SWIFT_BUILD_SYSTEM=swiftbuild bash "$wrapper" --skip-build --filter '^CompilerCoreTests\.RightSuite/targetTest'
reject_line --test-product "$TEST_DIR/args"
run_wrapper SWIFT_BUILD_SYSTEM=swiftbuild SWIFT_TEST_PRODUCT=ExplicitProduct bash "$wrapper" --filter '^CompilerCoreTests\.RightSuite/targetTest'
expect_line ExplicitProduct "$TEST_DIR/args"
run_wrapper SWIFT_BUILD_SYSTEM=swiftbuild SWIFT_TEST_PRODUCT=Ignored bash "$wrapper" --test-product CommandLineProduct --filter '^CompilerCoreTests\.RightSuite/targetTest'
expect_line CommandLineProduct "$TEST_DIR/args"
reject_line Ignored "$TEST_DIR/args"

# Preflight has an explicit escape hatch for generated or inherited tests.
run_wrapper SWIFT_TEST_SOURCE_PREFLIGHT=0 bash "$wrapper" --filter 'CompilerCoreTests.WrongSuite/targetTest'

# A successful SwiftPM exit must not disguise a no-match run, including for
# complex regexes that the source preflight cannot inspect.
if run_wrapper FAKE_NO_MATCH=1 bash "$wrapper" --filter 'NoSuchSuite|NoSuchOtherSuite'; then
    echo 'FAIL: accepted a no-match SwiftPM result' >&2; exit 1
fi
grep -qF 'no tests matched the filter' "$TEST_DIR/output"
if grep -qF 'All tests passed.' "$TEST_DIR/output"; then
    echo 'FAIL: reported success for an empty filtered run' >&2; exit 1
fi
if run_wrapper FAKE_NO_MATCH=zero bash "$wrapper" --filter 'NoSuchSuite|NoSuchOtherSuite'; then
    echo 'FAIL: accepted a zero-test Swift Testing run' >&2; exit 1
fi
run_wrapper FAKE_NO_MATCH=mixed bash "$wrapper" --filter 'AnySuite|AnotherSuite'

# Local jobs share the detected core count across the configured build slots.
run_wrapper SWIFT_BUILD_SLOTS=2 bash "$wrapper"
expect_line -j "$TEST_DIR/args"
expect_line 4 "$TEST_DIR/args"
run_wrapper SWIFT_BUILD_SLOTS=2 SWIFT_TEST_BUILD_JOBS=3 bash "$wrapper"
expect_line 3 "$TEST_DIR/args"
run_wrapper SWIFT_BUILD_SLOTS=2 bash "$wrapper" -j5
expect_line -j5 "$TEST_DIR/args"
reject_line -j "$TEST_DIR/args"
run_wrapper CI=true bash "$wrapper"
expect_line 8 "$TEST_DIR/args"
if run_wrapper SWIFT_BUILD_SLOTS=08 bash "$wrapper"; then
    echo 'FAIL: accepted an invalid build slot count' >&2; exit 1
fi
grep -qF 'SWIFT_BUILD_SLOTS must be a non-negative integer' "$TEST_DIR/output"

# Focused swift build invocations use the same slots and job policy as tests.
build_wrapper="$TEST_DIR/repo/Scripts/swift_build.sh"
run_wrapper SWIFT_BUILD_SLOTS=2 bash "$build_wrapper" --product kswiftc
expect_line build "$TEST_DIR/args"
expect_line --product "$TEST_DIR/args"
expect_line kswiftc "$TEST_DIR/args"
expect_line 4 "$TEST_DIR/args"
run_wrapper SWIFT_BUILD_SLOTS=2 SWIFT_BUILD_JOBS=3 bash "$build_wrapper" --target CompilerCore
expect_line 3 "$TEST_DIR/args"
run_wrapper SWIFT_BUILD_SLOTS=2 bash "$build_wrapper" --jobs=5
reject_line -j "$TEST_DIR/args"
expect_line --jobs=5 "$TEST_DIR/args"

echo 'PASS: Swift test filter, product, and build job selection'
