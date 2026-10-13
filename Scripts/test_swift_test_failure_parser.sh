#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmpout="$(mktemp)"
trap 'rm -f "$tmpout"' EXIT

# Exercise the actual parser without starting SwiftPM or a compiler build.
source <(sed -n '/^parse_failed_tests() {/,/^}/p' "$script_dir/swift_test.sh")
cat > "$tmpout" <<'OUTPUT'
◇ Test example() started.
✘ Test example(flag:) recorded an issue with 1 argument flag → true: Caught error: signal 4
✘ Test example(flag:) with 2 test cases failed after 1 second.
FAILED: LegacySuite/anotherTest
OUTPUT
declare -a failures=()
parse_failed_tests failures
[[ ${#failures[@]} == 2 ]]
[[ ${failures[0]} == 'example(flag:)' ]]
[[ ${failures[1]} == 'LegacySuite/anotherTest' ]]
printf 'PASS Swift Testing failures prevent crash-only retries\n'
