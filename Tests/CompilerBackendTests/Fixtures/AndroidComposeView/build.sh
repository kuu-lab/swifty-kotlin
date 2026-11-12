#!/usr/bin/env bash
set -euo pipefail

fixture=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repository=$(cd "$fixture/../../../.." && pwd)
compiler=${KSWIFTC:-"$repository/.build/debug/kswiftc"}
output="$fixture/build/kswiftk"
mkdir -p "$output"

"$compiler" --stdlib-only --emit jar -o "$output/kswiftk-stdlib.jar"
gradle -p "$fixture" "$@" assembleDebug
