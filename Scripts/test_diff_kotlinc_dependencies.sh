#!/usr/bin/env bash
# Test the real dependency-selection functions without Maven or compiler work.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-diff-dependencies.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Load only function definitions, stopping before the harness starts running.
awk '/^target_matches_import\(\)/ { copy = 1 }
     copy && /^if \[\[ -z "\$TARGET"/ { exit }
     copy { print }' "$SCRIPT_DIR/diff_kotlinc.sh" > "$TEMP_DIR/functions.sh"
source "$TEMP_DIR/functions.sh"

KOTLINC_COROUTINES_JAR="$TEMP_DIR/coroutines.jar"
KOTLINC_KOTLINX_IO_JAR="$TEMP_DIR/io.jar"
KOTLINC_KOTLINX_IO_BYTESTRING_JAR="$TEMP_DIR/bytestring.jar"
DOWNLOADS=""
FAIL_IO=0
ensure_coroutines_jar() { DOWNLOADS+="coroutines;"; }
ensure_kotlinx_io_jar() {
  DOWNLOADS+="io;"
  [[ "$FAIL_IO" == 0 ]]
}
ensure_kotlinx_io_bytestring_jar() { DOWNLOADS+="bytestring;"; }

check_selection() {
  local imports="$1" expected_classpath="$2" expected_downloads="$3"
  TARGET="$TEMP_DIR/case.kt"
  printf '%s\n' "$imports" > "$TARGET"
  KOTLINC_CLASSPATH=""
  DOWNLOADS=""
  ensure_kotlinc_classpath
  [[ "$KOTLINC_CLASSPATH" == "$expected_classpath" ]]
  [[ "$DOWNLOADS" == "$expected_downloads" ]]
}

check_selection 'fun main() {}' '' ''
check_selection 'import kotlinx.coroutines.*' "$KOTLINC_COROUTINES_JAR" 'coroutines;'
check_selection 'import kotlinx.io.Buffer' "$KOTLINC_KOTLINX_IO_JAR" 'io;'
check_selection 'import kotlinx.io.bytestring.ByteString' \
  "$KOTLINC_KOTLINX_IO_JAR:$KOTLINC_KOTLINX_IO_BYTESTRING_JAR" 'io;bytestring;'
check_selection $'import kotlinx.coroutines.runBlocking\nimport kotlinx.io.Buffer' \
  "$KOTLINC_COROUTINES_JAR:$KOTLINC_KOTLINX_IO_JAR" 'coroutines;io;'

# Recursion, spaces in paths, and non-Kotlin files in a directory.
mkdir -p "$TEMP_DIR/cases/nested dir"
printf '%s\n' 'import kotlinx.io.Buffer' > "$TEMP_DIR/cases/nested dir/io.kt"
printf '%s\n' 'import kotlinx.coroutines.*' > "$TEMP_DIR/cases/ignored.txt"
TARGET="$TEMP_DIR/cases"
KOTLINC_CLASSPATH=""
DOWNLOADS=""
ensure_kotlinc_classpath
[[ "$KOTLINC_CLASSPATH" == "$KOTLINC_KOTLINX_IO_JAR" && "$DOWNLOADS" == 'io;' ]]

# A supplied classpath bypasses downloads even for imports needing jars.
KOTLINC_CLASSPATH="$TEMP_DIR/manual.jar"
DOWNLOADS=""
ensure_kotlinc_classpath
[[ "$KOTLINC_CLASSPATH" == "$TEMP_DIR/manual.jar" && -z "$DOWNLOADS" ]]

# Failed dependency acquisition must not report a usable classpath.
FAIL_IO=1
KOTLINC_CLASSPATH=""
if ensure_kotlinc_classpath; then
  echo 'Expected io dependency acquisition to fail.' >&2
  exit 1
fi
[[ -z "$KOTLINC_CLASSPATH" ]]
echo 'PASS diff_kotlinc dependency selection'
