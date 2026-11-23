#!/usr/bin/env bash
# Builds the APK with kswiftc alone: it resolves the Compose runtime from
# Google Maven / Maven Central, compiles the Java bridge with javac, merges
# the library manifests and packages, dexes and signs the app.
set -euo pipefail

fixture=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repository=$(cd "$fixture/../../../.." && pwd)
compiler=${KSWIFTC:-"$repository/.build/debug/kswiftc"}
output="$fixture/build/outputs/apk/debug"
mkdir -p "$output"

"$compiler" "$fixture/MainActivity.kt" \
    "$fixture/src/main/java/org/swiftykotlin/composeprobe/ComposeCounterState.java" \
    --emit apk -o "$output/ComposeProbe-debug.apk" -include-runtime \
    --manifest "$fixture/src/main/AndroidManifest.xml" \
    --android-namespace org.swiftykotlin.composeprobe \
    --android-compile-sdk 36.1 --android-build-tools 36.1.0 \
    --android-min-api 24 --android-target-sdk 34 \
    --android-version-code 1 --android-version-name 1.0 --android-debuggable \
    --android-dependency androidx.compose.runtime:runtime-android:1.7.8 \
    "$@"
