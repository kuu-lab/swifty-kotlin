#!/usr/bin/env bash
set -euo pipefail

lean_bin=${LEAN:-lean}
case "$lean_bin" in
    /*) ;;
    */*) lean_bin="$PWD/$lean_bin" ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")/.."
build_parser=true
for argument in "$@"; do
    if [[ "$argument" == --skip-build ]]; then
        build_parser=false
    fi
done
if [[ "$build_parser" == true ]]; then
    LEAN="$lean_bin" bash Scripts/build_lean.sh
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-lean-tests.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
oracle="$work_dir/type-arguments.json"
(
    cd Sources/LeanParser
    lean_prefix=$("$lean_bin" --print-prefix)
    "$lean_prefix/bin/lake" build
    "$lean_prefix/bin/lake" env "$lean_bin" --run ../../Tests/Formal/TypeArguments.lean > "$oracle"
)
KSWIFTK_TYPE_ARGUMENTS_ORACLE="$oracle" bash Scripts/swift_test.sh "$@" \
    --no-parallel --filter '^CompilerCoreFrontendTests\.TypeArgumentsLeanParityTests/'
