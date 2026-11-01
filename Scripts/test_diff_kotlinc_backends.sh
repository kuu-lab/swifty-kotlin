#!/usr/bin/env bash
# Regression test for diff_kotlinc.sh backend lanes (DIFF_BACKEND=jvm/wasm):
# marker filtering, per-backend candidate compile/run wiring, engine
# selection, and the zero-marked-cases guard. Uses fake compiler/java/engine
# stubs; no real kotlinc, java, node, or wasmtime is exercised.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-diff-backends-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

FAKE_BIN_DIR="$TEMP_DIR/fake_bin"
mkdir -p "$FAKE_BIN_DIR"

# Fake kswiftc: emits a real zip "jar" (unzip must read its manifest for
# jar_main_class), opaque bytes for wasm, an executable script for native,
# and a manifest.json for --stdlib-only builds.
cat >"$FAKE_BIN_DIR/fake_kswiftc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$KSWIFTC_LOG"
out=""
src=""
emit=""
target=""
stdlib_only=0
prev=""
for arg in "$@"; do
  case "$prev" in
    -o) out="$arg" ;;
    --emit) emit="$arg" ;;
    --target) target="$arg" ;;
  esac
  if [[ "$arg" == "--stdlib-only" ]]; then
    stdlib_only=1
  fi
  if [[ "$arg" == *.kt ]]; then
    src="$arg"
  fi
  prev="$arg"
done
[[ -n "$out" ]] || { echo "fake_kswiftc: missing -o" >&2; exit 91; }

write_jar() {
  python3 - "$1" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\r\nMain-Class: FakeKt\r\n\r\n")
PY
}

if [[ "$stdlib_only" -eq 1 && "$emit" == "jar" ]]; then
  write_jar "$out"
  exit 0
fi
if [[ "$stdlib_only" -eq 1 && "$emit" == "library" ]]; then
  mkdir -p "$out"
  echo '{}' >"$out/manifest.json"
  exit 0
fi
if [[ "$emit" == "jar" ]]; then
  write_jar "$out"
  exit 0
fi
if [[ -n "$target" ]]; then
  printf 'FAKE-WASM' >"$out"
  exit 0
fi
cat >"$out" <<'PROGRAM'
#!/usr/bin/env bash
printf 'case-ok\n'
PROGRAM
chmod +x "$out"
exit 0
EOF
chmod +x "$FAKE_BIN_DIR/fake_kswiftc"

# Fake kotlinc: -version and `... -d ref.jar` (writes a zip jar).
cat >"$FAKE_BIN_DIR/fake_kotlinc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$KOTLINC_LOG"
if [[ "${1:-}" == "-version" ]]; then
  echo "fake kotlinc 2.4.20"
  exit 0
fi
out=""
prev=""
for arg in "$@"; do
  [[ "$prev" == "-d" ]] && out="$arg"
  prev="$arg"
done
[[ -n "$out" ]] || { echo "fake_kotlinc: missing -d" >&2; exit 92; }
python3 - "$out" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\r\nMain-Class: RefKt\r\n\r\n")
PY
EOF
chmod +x "$FAKE_BIN_DIR/fake_kotlinc"

# Fake java/engine stubs log their argv and print the shared expected output
# so ref and candidate runs always agree.
for stub in fake_java fake_node fake_wasmtime; do
  cat >"$FAKE_BIN_DIR/$stub" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
printf 'case-ok\n'
EOF
  chmod +x "$FAKE_BIN_DIR/$stub"
done

CASES_DIR="$TEMP_DIR/cases"
mkdir -p "$CASES_DIR"
cat >"$CASES_DIR/marked_both.kt" <<'KOTLIN'
// DIFF_JVM
// DIFF_WASM
fun main() { println("case-ok") }
KOTLIN
cat >"$CASES_DIR/marked_jvm_only.kt" <<'KOTLIN'
// DIFF_JVM
fun main() { println("case-ok") }
KOTLIN
cat >"$CASES_DIR/unmarked.kt" <<'KOTLIN'
fun main() { println("case-ok") }
KOTLIN

UNMARKED_CASES_DIR="$TEMP_DIR/unmarked_cases"
mkdir -p "$UNMARKED_CASES_DIR"
cp "$CASES_DIR/unmarked.kt" "$UNMARKED_CASES_DIR/unmarked.kt"

KOTLINC_LOG="$TEMP_DIR/kotlinc.log"
KSWIFTC_LOG="$TEMP_DIR/kswiftc.log"
STUB_LOG="$TEMP_DIR/stub.log"
OUTPUT_LOG="$TEMP_DIR/output.log"

run_diff() {
  set +e
  KOTLINC="$FAKE_BIN_DIR/fake_kotlinc" \
  KSWIFTC="$FAKE_BIN_DIR/fake_kswiftc" \
  JAVA_BIN="$FAKE_BIN_DIR/fake_java" \
  NODE_BIN="$FAKE_BIN_DIR/fake_node" \
  WASMTIME_BIN="$FAKE_BIN_DIR/fake_wasmtime" \
  DIFF_REQUIRE_JDK21=0 \
  DIFF_ARTIFACT_ROOT="$TEMP_DIR/artifacts" \
  KOTLINC_LOG="$KOTLINC_LOG" \
  KSWIFTC_LOG="$KSWIFTC_LOG" \
  STUB_LOG="$STUB_LOG" \
  "$@" >"$OUTPUT_LOG" 2>&1
  local rc=$?
  set -e
  return "$rc"
}

fail() {
  echo "FAIL: $1" >&2
  echo "--- diff_kotlinc.sh output ---" >&2
  cat "$OUTPUT_LOG" >&2
  exit 1
}

# --- native default keeps every case regardless of markers ---
mkdir -p "$TEMP_DIR/native_stdlib"
echo '{}' >"$TEMP_DIR/native_stdlib/manifest.json"
: >"$KOTLINC_LOG"; : >"$KSWIFTC_LOG"; : >"$STUB_LOG"
run_diff env DIFF_STDLIB_LIBRARY="$TEMP_DIR/native_stdlib" bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" --no-parallel "$CASES_DIR" \
  || fail "native sweep should pass"
grep -qF "Backend: native" "$OUTPUT_LOG" || fail "native run should report Backend: native"
grep -qF "Summary: total=3 failed=0 passed=3 skipped=0" "$OUTPUT_LOG" || fail "native sweep should run all 3 cases"
grep -qF -- "--stdlib-library" "$KSWIFTC_LOG" || fail "native candidate compile should use --stdlib-library"

# --- DIFF_SKIP_NATIVE keeps a JVM-lane case out of the native lane only ---
NATIVE_SKIP_CASES_DIR="$TEMP_DIR/native_skip_cases"
mkdir -p "$NATIVE_SKIP_CASES_DIR"
cp "$CASES_DIR/unmarked.kt" "$NATIVE_SKIP_CASES_DIR/unmarked.kt"
cat >"$NATIVE_SKIP_CASES_DIR/jvm_lane_only.kt" <<'KOTLIN'
// DIFF_JVM
// DIFF_SKIP_NATIVE: needs JVM-only stdlib surface
fun main() { println("case-ok") }
KOTLIN
run_diff env DIFF_STDLIB_LIBRARY="$TEMP_DIR/native_stdlib" bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" --no-parallel "$NATIVE_SKIP_CASES_DIR" \
  || fail "native sweep with a DIFF_SKIP_NATIVE case should pass"
grep -qF "SKIP $NATIVE_SKIP_CASES_DIR/jvm_lane_only.kt (DIFF_BACKEND=native)" "$OUTPUT_LOG" || fail "DIFF_SKIP_NATIVE case should SKIP in native lane"
grep -qF "Summary: total=1 failed=0 passed=1 skipped=1" "$OUTPUT_LOG" || fail "native sweep should run 1 case, skip the DIFF_SKIP_NATIVE one"
run_diff env DIFF_STDLIB_LIBRARY="$TEMP_DIR/native_stdlib" bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" --no-parallel "$NATIVE_SKIP_CASES_DIR/jvm_lane_only.kt" \
  || fail "single DIFF_SKIP_NATIVE file should report a skip, not fail"
grep -qF "Summary: total=0 failed=0 passed=0 skipped=1" "$OUTPUT_LOG" || fail "single DIFF_SKIP_NATIVE file should be skipped in native lane"
run_diff env DIFF_STDLIB_LIBRARY="$TEMP_DIR/native_stdlib" bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" --no-parallel --force-run-skipped "$NATIVE_SKIP_CASES_DIR/jvm_lane_only.kt" \
  || fail "--force-run-skipped should run a DIFF_SKIP_NATIVE file natively"
grep -qF "Summary: total=1 failed=0 passed=1 skipped=0" "$OUTPUT_LOG" || fail "--force-run-skipped should override DIFF_SKIP_NATIVE"
run_diff env DIFF_BACKEND=jvm bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" --no-parallel "$NATIVE_SKIP_CASES_DIR" \
  || fail "jvm sweep with a DIFF_SKIP_NATIVE case should pass"
grep -qF "PASS $NATIVE_SKIP_CASES_DIR/jvm_lane_only.kt" "$OUTPUT_LOG" || fail "DIFF_SKIP_NATIVE case should still PASS in jvm lane"

# --- jvm lane runs only marked cases through jar pipeline ---
: >"$KOTLINC_LOG"; : >"$KSWIFTC_LOG"; : >"$STUB_LOG"
run_diff env DIFF_BACKEND=jvm bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" --no-parallel "$CASES_DIR" \
  || fail "jvm sweep should pass"
grep -qF "Backend: jvm" "$OUTPUT_LOG" || fail "jvm run should report Backend: jvm"
grep -qF "PASS $CASES_DIR/marked_both.kt" "$OUTPUT_LOG" || fail "DIFF_JVM case should PASS in jvm lane"
grep -qF "PASS $CASES_DIR/marked_jvm_only.kt" "$OUTPUT_LOG" || fail "DIFF_JVM-only case should PASS in jvm lane"
grep -qF "SKIP $CASES_DIR/unmarked.kt (DIFF_BACKEND=jvm)" "$OUTPUT_LOG" || fail "unmarked case should SKIP in jvm lane"
grep -qF "Summary: total=2 failed=0 passed=2 skipped=1" "$OUTPUT_LOG" || fail "jvm sweep should run 2 cases, skip 1"
grep -qF -- "--emit jar" "$KSWIFTC_LOG" || fail "jvm lane should compile with --emit jar"
grep -qF -- "--stdlib-only --emit jar" "$KSWIFTC_LOG" || fail "jvm lane should build the shared stdlib jar"
grep -qF -- "-cp" "$STUB_LOG" || fail "jvm lane should run the candidate via java -cp"
grep -qF -- "-Xverify:all" "$STUB_LOG" || fail "jvm candidate run should verify bytecode"
grep -qF -- "FakeKt" "$STUB_LOG" || fail "jvm candidate run should use the manifest Main-Class"

# --- single named file runs without a marker ---
run_diff env DIFF_BACKEND=jvm bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" --no-parallel "$UNMARKED_CASES_DIR/unmarked.kt" \
  || fail "single-file jvm run should pass without a marker"
grep -qF "Summary: total=1 failed=0 passed=1 skipped=0" "$OUTPUT_LOG" || fail "single unmarked file should still run in jvm lane"

# --- wasm lane: node engine runs only DIFF_WASM-marked cases ---
: >"$KOTLINC_LOG"; : >"$KSWIFTC_LOG"; : >"$STUB_LOG"
run_diff env DIFF_BACKEND=wasm DIFF_ENGINE=node bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" --no-parallel "$CASES_DIR" \
  || fail "wasm/node sweep should pass"
grep -qF "PASS $CASES_DIR/marked_both.kt" "$OUTPUT_LOG" || fail "DIFF_WASM case should PASS in wasm lane"
grep -qF "SKIP $CASES_DIR/marked_jvm_only.kt (DIFF_BACKEND=wasm)" "$OUTPUT_LOG" || fail "jvm-only case should SKIP in wasm lane"
grep -qF "SKIP $CASES_DIR/unmarked.kt (DIFF_BACKEND=wasm)" "$OUTPUT_LOG" || fail "unmarked case should SKIP in wasm lane"
grep -qF "Summary: total=1 failed=0 passed=1 skipped=2" "$OUTPUT_LOG" || fail "wasm sweep should run 1 case, skip 2"
grep -qF -- "--target wasm32-wasi" "$KSWIFTC_LOG" || fail "wasm lane should compile with --target wasm32-wasi"
if grep -qF -- "--stdlib-library" "$KSWIFTC_LOG"; then
  fail "wasm lane must not use the native --stdlib-library path"
fi
grep -qF "wasi_node_runner.mjs" "$STUB_LOG" || fail "wasm/node lane should invoke the node WASI runner"
grep -qF "candidate.wasm" "$STUB_LOG" || fail "wasm/node lane should run the emitted .wasm module"

# --- wasm lane: wasmtime engine ---
: >"$KOTLINC_LOG"; : >"$KSWIFTC_LOG"; : >"$STUB_LOG"
run_diff env DIFF_BACKEND=wasm DIFF_ENGINE=wasmtime bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" --no-parallel "$CASES_DIR" \
  || fail "wasm/wasmtime sweep should pass"
grep -qF "PASS $CASES_DIR/marked_both.kt" "$OUTPUT_LOG" || fail "DIFF_WASM case should PASS under wasmtime"
if grep -qF "wasi_node_runner.mjs" "$STUB_LOG"; then
  fail "wasmtime lane must not invoke the node runner"
fi
grep -qE -- "run .*/candidate\.wasm" "$STUB_LOG" || fail "wasmtime lane should run via 'wasmtime run <module>'"

# --- zero marked cases is an error, not a vacuous pass ---
if run_diff env DIFF_BACKEND=jvm bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" --no-parallel "$UNMARKED_CASES_DIR"; then
  fail "jvm sweep over unmarked-only directory should fail"
fi
grep -qF "ran zero cases" "$OUTPUT_LOG" || fail "empty marked set should explain the zero-case failure"

# --- invalid backend / engine values are rejected ---
if run_diff env DIFF_BACKEND=bogus bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" --no-parallel "$CASES_DIR"; then
  fail "invalid DIFF_BACKEND should be rejected"
fi
grep -qF "DIFF_BACKEND must be native, jvm, or wasm" "$OUTPUT_LOG" || fail "invalid backend should name the accepted values"

if run_diff env DIFF_BACKEND=wasm DIFF_ENGINE=bogus bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" --no-parallel "$CASES_DIR"; then
  fail "invalid DIFF_ENGINE should be rejected"
fi
grep -qF "DIFF_ENGINE must be node or wasmtime" "$OUTPUT_LOG" || fail "invalid engine should name the accepted values"

echo "OK: diff_kotlinc.sh backend lanes (jvm/wasm markers, engines, zero-case guard) work"
