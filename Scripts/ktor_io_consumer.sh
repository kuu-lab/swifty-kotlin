#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
TARGET="arm64-apple-macosx"
KTOR_URL="https://github.com/ktorio/ktor.git"
KTOR_COMMIT="111c5807d0a9004c8e0f17ae01e12a71aae56a29"
KOTLINX_IO_COMMIT="362bdc35e159bad6da1e08101c8321792d762281"
COROUTINES_COMMIT="8564f65764d3d05893cec026c6e94250e2b23874"
KOTLIN_VERSION="2.3.21"
KOTLINX_IO_VERSION="0.9.1"
COROUTINES_VERSION="1.11.0"
ATOMICFU_VERSION="0.33.0"

CACHE_DIR="${KTOR_IO_CACHE_DIR:-${TMPDIR:-/tmp}/ktor-io-consumer-111c5807}"
KTOR_DIR="$CACHE_DIR/ktor"
OUT_DIR="${KTOR_IO_OUT_DIR:-$CACHE_DIR/out}"
KTOR_IO_DIR="$KTOR_DIR/ktor-io"
STDLIB_KKLIB="${KTOR_IO_STDLIB_KKLIB:-$OUT_DIR/KSwiftKStdlib.kklib}"
CONSUMER_SOURCE="$ROOT_DIR/Scripts/ktor_io_consumer.kt"
EXPECTED_OUTPUT="$ROOT_DIR/Scripts/ktor_io_consumer.expected"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

if [[ ! -x "$KSWIFTC" ]]; then
  fail "kswiftc not found at $KSWIFTC; run 'swift build' first."
fi

mkdir -p "$CACHE_DIR" "$OUT_DIR"

if [[ ! -d "$KTOR_DIR/.git" ]]; then
  git clone --filter=blob:none --no-checkout "$KTOR_URL" "$KTOR_DIR"
  git -C "$KTOR_DIR" fetch --depth 1 origin "$KTOR_COMMIT"
  git -C "$KTOR_DIR" sparse-checkout init --cone
  git -C "$KTOR_DIR" sparse-checkout set ktor-io
  git -C "$KTOR_DIR" checkout --detach "$KTOR_COMMIT"
fi

actual_commit="$(git -C "$KTOR_DIR" rev-parse HEAD)"
[[ "$actual_commit" == "$KTOR_COMMIT" ]] \
  || fail "Ktor checkout is $actual_commit; expected pinned commit $KTOR_COMMIT. Set KTOR_IO_CACHE_DIR to a clean cache."
[[ -z "$(git -C "$KTOR_DIR" status --porcelain)" ]] \
  || fail "Ktor checkout has local changes: $KTOR_DIR"

assert_catalog_version() {
  local key="$1"
  local version="$2"
  if ! git -C "$KTOR_DIR" show "$KTOR_COMMIT:gradle/libs.versions.toml" \
    | grep -Fqx "$key = \"$version\""; then
    fail "Ktor $KTOR_COMMIT version catalog does not pin $key to $version."
  fi
}

assert_catalog_version kotlin "$KOTLIN_VERSION"
assert_catalog_version kotlinx-io "$KOTLINX_IO_VERSION"
assert_catalog_version coroutines "$COROUTINES_VERSION"
assert_catalog_version atomicfu "$ATOMICFU_VERSION"

source_roots=(common nonJvm jvmAndPosix posix darwin)
sources=()
for root in "${source_roots[@]}"; do
  [[ -d "$KTOR_IO_DIR/$root/src" ]] || fail "Missing pinned source root: ktor-io/$root/src"
  while IFS= read -r file; do sources+=("$file"); done \
    < <(find "$KTOR_IO_DIR/$root/src" -type f -name '*.kt' | sort)
done
[[ "${#sources[@]}" -eq 63 ]] \
  || fail "Pinned Ktor macOS source set changed: expected 63 files, found ${#sources[@]}"

printf 'Ktor 3.6.0 commit: %s\n' "$KTOR_COMMIT"
printf 'kotlinx-io %s commit: %s\n' "$KOTLINX_IO_VERSION" "$KOTLINX_IO_COMMIT"
printf 'kotlinx-coroutines %s commit: %s\n' "$COROUTINES_VERSION" "$COROUTINES_COMMIT"
printf 'atomicfu %s; Kotlin %s; target %s\n' "$ATOMICFU_VERSION" "$KOTLIN_VERSION" "$TARGET"
printf 'Source roots: %s (%s files)\n' "${source_roots[*]}" "${#sources[@]}"

if [[ -n "${KTOR_IO_STDLIB_KKLIB:-}" ]]; then
  [[ -d "$STDLIB_KKLIB" ]] || fail "Bundled stdlib artifact not found: $STDLIB_KKLIB"
  printf 'Using bundled stdlib artifact: %s\n' "$STDLIB_KKLIB"
else
  rm -rf "$STDLIB_KKLIB"
  stdlib_log="$OUT_DIR/stdlib.log"
  if ! "$KSWIFTC" --stdlib-only --emit library -O0 --target "$TARGET" \
    -o "$STDLIB_KKLIB" >"$stdlib_log" 2>&1; then
    cat "$stdlib_log" >&2
    fail "Failed to build a fresh bundled stdlib artifact; see $stdlib_log"
  fi
fi

failed=0
for optimization in 0 2; do
  module_library="$OUT_DIR/ktor_io_macos_O$optimization.kklib"
  module_log="$OUT_DIR/ktor_io_macos_O$optimization.log"
  consumer_binary="$OUT_DIR/ktor_io_consumer_O$optimization"
  consumer_log="$OUT_DIR/ktor_io_consumer_O$optimization.log"

  rm -rf "$module_library" "$consumer_binary"
  if ! "$KSWIFTC" --emit library -m ktor_io_macos -O"$optimization" \
    --target "$TARGET" --stdlib-library "$STDLIB_KKLIB" -o "$module_library" \
    "${sources[@]}" >"$module_log" 2>&1; then
    printf 'FAIL Ktor library compile O%s; diagnostics: %s\n' "$optimization" "$module_log" >&2
    rg 'error KSWIFTK' "$module_log" | head -30 >&2 || true
    failed=1
    continue
  fi

  if ! "$KSWIFTC" --emit executable -m ktor_io_consumer -O"$optimization" \
    --target "$TARGET" --stdlib-library "$STDLIB_KKLIB" -I "$module_library" \
    -o "$consumer_binary" "$CONSUMER_SOURCE" >"$consumer_log" 2>&1; then
    printf 'FAIL consumer compile/link O%s; diagnostics: %s\n' "$optimization" "$consumer_log" >&2
    rg 'error KSWIFTK' "$consumer_log" | head -30 >&2 || true
    failed=1
    continue
  fi

  if ! python3 - "$consumer_binary" "$EXPECTED_OUTPUT" <<'PY'
import pathlib
import subprocess
import sys

executable, expected_path = sys.argv[1:]
try:
    result = subprocess.run([executable], capture_output=True, timeout=30, check=False)
except subprocess.TimeoutExpired as error:
    print(f"FAIL execution timed out after 30 seconds: {executable}", file=sys.stderr)
    if error.stdout:
        print(repr(error.stdout), file=sys.stderr)
    sys.exit(124)

if result.returncode != 0:
    print(f"FAIL execution exited {result.returncode}: {executable}", file=sys.stderr)
    print(result.stderr.decode("utf-8", errors="replace"), file=sys.stderr)
    sys.exit(result.returncode)

expected = pathlib.Path(expected_path).read_bytes()
if result.stdout != expected:
    print(f"FAIL output mismatch: {executable}", file=sys.stderr)
    print(f"expected: {expected!r}", file=sys.stderr)
    print(f"actual:   {result.stdout!r}", file=sys.stderr)
    print(result.stderr.decode("utf-8", errors="replace"), file=sys.stderr)
    sys.exit(1)

if result.stderr:
    print(f"FAIL unexpected stderr: {executable}", file=sys.stderr)
    print(result.stderr.decode("utf-8", errors="replace"), file=sys.stderr)
    sys.exit(1)

print(f"PASS output matches {expected_path} ({len(expected)} bytes)")
PY
  then
    failed=1
    continue
  fi

  printf 'PASS ktor_io_macos compile + consumer link/run O%s\n' "$optimization"
done

if [[ "$failed" -ne 0 ]]; then
  fail "Ktor consumer end-to-end validation failed; full logs are under $OUT_DIR"
fi
