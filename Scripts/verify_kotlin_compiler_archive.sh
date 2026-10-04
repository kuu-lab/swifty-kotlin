#!/usr/bin/env bash
# Verify the repository-pinned Kotlin compiler archive before extracting it.
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <archive.zip> <expected-sha256> <install-dir> <expected-version>" >&2
  exit 2
fi

archive_path="$1"
expected_sha256="$2"
install_dir="$3"
expected_version="$4"

if [[ ! "$expected_sha256" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "Invalid expected SHA-256 for Kotlin compiler archive" >&2
  exit 2
fi
if [[ ! -s "$archive_path" ]]; then
  echo "Kotlin compiler archive is missing or empty: $archive_path" >&2
  exit 1
fi
if ! command -v sha256sum >/dev/null 2>&1; then
  echo "sha256sum is required to verify the Kotlin compiler archive" >&2
  exit 1
fi

actual_sha256="$(sha256sum "$archive_path" | awk '{print $1}')"
if [[ "$actual_sha256" != "$expected_sha256" ]]; then
  echo "Kotlin compiler archive checksum mismatch" >&2
  echo "Expected: $expected_sha256" >&2
  echo "Actual:   $actual_sha256" >&2
  rm -rf "$install_dir"
  exit 1
fi

rm -rf "$install_dir"
mkdir -p "$install_dir"
unzip -q "$archive_path" -d "$install_dir"

compiler="$install_dir/kotlinc/bin/kotlinc"
if [[ ! -x "$compiler" ]]; then
  echo "Verified Kotlin compiler archive does not contain executable kotlinc" >&2
  rm -rf "$install_dir"
  exit 1
fi

version_output="$("$compiler" -version 2>&1)" || {
  echo "Verified Kotlin compiler failed to report its version" >&2
  echo "$version_output" >&2
  rm -rf "$install_dir"
  exit 1
}
if [[ "$version_output" != *"kotlinc-jvm $expected_version"* ]]; then
  echo "Unexpected Kotlin compiler version; expected $expected_version" >&2
  echo "$version_output" >&2
  rm -rf "$install_dir"
  exit 1
fi
