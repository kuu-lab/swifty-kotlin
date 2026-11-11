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

# Use a small Android header JAR for classpath import. AGP packages the full
# AndroidX artifacts, and the Android framework is supplied by the device.
python3 - "$android_jar" "$output" <<'PY'
import sys
from pathlib import Path
from zipfile import ZipFile

output = Path(sys.argv[2])
inputs = {
    Path(sys.argv[1]): [
        'android/app/Activity',
        'android/content/Context',
        'android/content/ContextWrapper',
        'android/os/BaseBundle',
        'android/os/Bundle',
        'android/view/ContextThemeWrapper',
        'android/view/View',
        'android/view/ViewGroup',
    ],
    output / 'activity.jar': ['androidx/activity/ComponentActivity'],
    output / 'core.jar': ['androidx/core/app/ComponentActivity'],
}
with ZipFile(output / 'android-api.jar', 'w') as headers:
    for path, classes in inputs.items():
        with ZipFile(path) as source:
            for name in classes:
                entry = name + '.class'
                headers.writestr(entry, source.read(entry))
PY

"$compiler" "$fixture/MainActivity.kt" --emit class \
    --classpath "$output/android-api.jar:$output/runtime.jar:$output/ui.jar:$output/foundation.jar:$output/layout.jar:$output/material3.jar:$output/kswiftk-stdlib.jar" \
    -o "$output/counter"
jar cf "$output/counter.jar" -C "$output/counter" .
gradle -p "$fixture" "$@" assembleDebug
