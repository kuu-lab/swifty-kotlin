#!/usr/bin/env bash
set -euo pipefail

fixture=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repository=$(cd "$fixture/../../../.." && pwd)
compiler=${KSWIFTC:-"$repository/.build/debug/kswiftc"}
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
android_jar=${sdk:?Set ANDROID_HOME to the Android SDK directory}/platforms/android-36.1/android.jar
output="$fixture/build/kswiftk"
mkdir -p "$output"

gradle -p "$fixture" "$@" extractComposeRuntime
"$compiler" --stdlib-only --emit jar -o "$output/kswiftk-stdlib.jar"
javac --release 8 -cp "$android_jar:$output/compose-runtime.jar:$output/kswiftk-stdlib.jar" \
    -d "$output/bridge" "$fixture/src/main/java/org/swiftykotlin/composeprobe/ComposeCounterState.java"
jar cf "$output/bridge.jar" -C "$output/bridge" .

# Keep classpath import limited to the Android framework types the activity uses.
# AGP uses the full SDK and the original Compose AAR when packaging the APK.
python3 - "$android_jar" "$output/android-api.jar" <<'PY'
import sys
from zipfile import ZipFile

classes = [
    'android/app/Activity',
    'android/content/Context',
    'android/content/ContextWrapper',
    'android/os/BaseBundle',
    'android/os/Bundle',
    'android/view/ContextThemeWrapper',
    'android/view/View',
    'android/view/View$OnClickListener',
    'android/view/ViewGroup',
    'android/widget/Button',
    'android/widget/LinearLayout',
    'android/widget/TextView',
]
with ZipFile(sys.argv[1]) as sdk, ZipFile(sys.argv[2], 'w') as headers:
    for name in classes:
        entry = name + '.class'
        headers.writestr(entry, sdk.read(entry))
PY

"$compiler" "$fixture/MainActivity.kt" --emit class \
    --classpath "$output/android-api.jar:$output/bridge.jar:$output/kswiftk-stdlib.jar" \
    -o "$output/activity"
jar cf "$output/activity.jar" -C "$output/activity" .
gradle -p "$fixture" "$@" assembleDebug
