#!/usr/bin/env bash
set -euo pipefail

fixture=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repository=$(cd "$fixture/../../../.." && pwd)
compiler=${KSWIFTC:-"$repository/.build/debug/kswiftc"}
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
android_jar=${sdk:?Set ANDROID_HOME to the Android SDK directory}/platforms/android-36.1/android.jar
output="$fixture/build/kswiftk"
mkdir -p "$output"

gradle -p "$fixture" "$@" extractComposeApis
"$compiler" --stdlib-only --emit jar -o "$output/kswiftk-stdlib.jar"
javac --release 8 -cp "$android_jar:$output/compose-runtime.jar:$output/compose-ui.jar:$output/kswiftk-stdlib.jar" \
    -d "$output/bridge" "$fixture/src/main/java/org/swiftykotlin/composeprobe/CounterRenderer.java"
jar cf "$output/bridge.jar" -C "$output/bridge" .
"$compiler" "$fixture/Counter.kt" --emit class \
    --classpath "$output/compose-runtime.jar:$output/bridge.jar:$output/kswiftk-stdlib.jar" \
    -o "$output/counter"
jar cf "$output/counter.jar" -C "$output/counter" .
gradle -p "$fixture" "$@" assembleDebug
