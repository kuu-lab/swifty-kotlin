#!/usr/bin/env bash
# Regression test for pinned Kotlin compiler archive verification and install.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
VERIFY_SCRIPT="$SCRIPT_DIR/verify_kotlin_compiler_archive.sh"
WORKFLOW="$SCRIPT_DIR/../.github/workflows/ci.yml"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-kotlinc-archive-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

expected_kotlin_sha256="c8d546f9ff433b529fb0ad43feceb39831040cae2ca8d17e7df46364368c9a9e"
if ! grep -Fq "KOTLIN_COMPILER_SHA256: \"$expected_kotlin_sha256\"" "$WORKFLOW"; then
  echo "FAIL: CI must pin the reviewed Kotlin compiler SHA-256" >&2
  exit 1
fi
if ! grep -Fq 'bash Scripts/verify_kotlin_compiler_archive.sh' "$WORKFLOW"; then
  echo "FAIL: CI must verify the Kotlin compiler archive before adding it to PATH" >&2
  exit 1
fi
verify_diff_job="$(awk '
  /^  verify-diff:$/ { in_verify_diff = 1 }
  in_verify_diff && /^  [a-z][a-z0-9-]*:$/ && $0 != "  verify-diff:" { exit }
  in_verify_diff { print }
' "$WORKFLOW")"
if ! grep -Fq 'run: bash Scripts/test_verify_kotlin_compiler_archive.sh' <<<"$verify_diff_job"; then
  echo "FAIL: CI must run the Kotlin compiler integrity regression policy test" >&2
  exit 1
fi
verify_line="$(grep -nF 'bash Scripts/verify_kotlin_compiler_archive.sh' <<<"$verify_diff_job" | head -n 1 | cut -d: -f1)"
path_line="$(grep -nF 'echo "${KOTLIN_DIR}/kotlinc/bin" >> "$GITHUB_PATH"' <<<"$verify_diff_job" | head -n 1 | cut -d: -f1)"
if [[ -z "$verify_line" || -z "$path_line" || "$verify_line" -ge "$path_line" ]]; then
  echo "FAIL: CI must verify the archive before adding the compiler to PATH" >&2
  exit 1
fi
if ! grep -Fq 'key: kotlin-tools-${{ env.KOTLIN_VERSION }}-${{ env.KOTLIN_COMPILER_SHA256 }}-coroutines-${{ env.KOTLINX_COROUTINES_VERSION }}' "$WORKFLOW"; then
  echo "FAIL: Kotlin compiler cache key must include the pinned archive SHA-256" >&2
  exit 1
fi
if ! grep -Fq '${{ runner.temp }}/kotlin-tools' "$WORKFLOW"; then
  echo "FAIL: Kotlin dependency jars must remain in the cached tools directory" >&2
  exit 1
fi
if grep -Fq 'unzip -q "$zip_path"' "$WORKFLOW"; then
  echo "FAIL: CI must not extract the Kotlin compiler archive outside the verifier" >&2
  exit 1
fi

SOURCE_DIR="$TEST_DIR/source"
mkdir -p "$SOURCE_DIR/kotlinc/bin"
cat >"$SOURCE_DIR/kotlinc/bin/kotlinc" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-version" ]]; then
  echo "info: kotlinc-jvm 2.3.10 (archive integrity test)"
  exit 0
fi
echo "unexpected invocation" >&2
exit 1
EOF
chmod +x "$SOURCE_DIR/kotlinc/bin/kotlinc"

valid_archive="$TEST_DIR/kotlin-compiler-valid.zip"
(cd "$SOURCE_DIR" && zip -qr "$valid_archive" kotlinc)
expected_sha256="$(sha256sum "$valid_archive" | awk '{print $1}')"
valid_install="$TEST_DIR/valid-install"
bash "$VERIFY_SCRIPT" "$valid_archive" "$expected_sha256" "$valid_install" "2.3.10"
[[ -x "$valid_install/kotlinc/bin/kotlinc" ]]

# Keep a pre-existing install in place to prove a corrupted cache cannot leave
# a previously extracted compiler available after verification fails.
corrupt_archive="$TEST_DIR/kotlin-compiler-corrupt.zip"
cp "$valid_archive" "$corrupt_archive"
printf 'X' | dd of="$corrupt_archive" bs=1 seek=20 conv=notrunc 2>/dev/null
corrupt_install="$TEST_DIR/corrupt-install"
mkdir -p "$corrupt_install/kotlinc/bin"
touch "$corrupt_install/kotlinc/bin/kotlinc"
if bash "$VERIFY_SCRIPT" "$corrupt_archive" "$expected_sha256" "$corrupt_install" "2.3.10" >"$TEST_DIR/corrupt.log" 2>&1; then
  echo "FAIL: checksum mismatch was accepted" >&2
  exit 1
fi
if ! grep -Fq 'Kotlin compiler archive checksum mismatch' "$TEST_DIR/corrupt.log"; then
  cat "$TEST_DIR/corrupt.log" >&2
  echo "FAIL: checksum mismatch did not fail at the archive verification boundary" >&2
  exit 1
fi
if [[ -e "$corrupt_install" ]]; then
  echo "FAIL: failed verification left an extracted compiler available" >&2
  exit 1
fi

# A correctly checksummed archive with the wrong tool version is also refused.
wrong_version_archive="$TEST_DIR/kotlin-compiler-wrong-version.zip"
cp "$valid_archive" "$wrong_version_archive"
wrong_version_sha256="$(sha256sum "$wrong_version_archive" | awk '{print $1}')"
if bash "$VERIFY_SCRIPT" "$wrong_version_archive" "$wrong_version_sha256" "$TEST_DIR/wrong-version-install" "2.3.11" >"$TEST_DIR/wrong-version.log" 2>&1; then
  echo "FAIL: unexpected compiler version was accepted" >&2
  exit 1
fi
if ! grep -Fq 'Unexpected Kotlin compiler version; expected 2.3.11' "$TEST_DIR/wrong-version.log"; then
  cat "$TEST_DIR/wrong-version.log" >&2
  echo "FAIL: version mismatch did not fail at the compiler version check" >&2
  exit 1
fi

echo "PASS: Kotlin compiler archive checksum and version verification"
