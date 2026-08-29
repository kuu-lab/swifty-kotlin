#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$ROOT_DIR/Tests/ARCH-025/manifest.tsv"
UPSTREAM_URL="${ARCH025_UPSTREAM_URL:-https://github.com/JetBrains/kotlin.git}"
UPSTREAM_REF="v2.3.10"
UPSTREAM_REVISION="679366a83f99851b42f64795f10ed803ff011c73"
DRY_RUN=0
VERIFY_ONLY=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--dry-run|--verify]

Import the selected ARCH-025 fixtures from the pinned Kotlin revision.

Options:
  --dry-run  Resolve and hash the upstream files without changing the worktree.
  --verify   Require all checked-in fixtures to match the manifest hashes.
  -h, --help Show this help.
USAGE
}

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

hash_upstream_file() {
  if command -v shasum >/dev/null 2>&1; then
    git -C "$1" show "${UPSTREAM_REVISION}:$2" | shasum -a 256 | awk '{print $1}'
  else
    git -C "$1" show "${UPSTREAM_REVISION}:$2" | sha256sum | awk '{print $1}'
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --verify)
      VERIFY_ONLY=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ $VERIFY_ONLY -eq 1 ]]; then
  DRY_RUN=1
fi

[[ -f "$MANIFEST" ]] || { echo "Manifest not found: $MANIFEST" >&2; exit 1; }

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/arch025-import.XXXXXX")"
trap 'rm -rf "$TEMP_ROOT"' EXIT
UPSTREAM_DIR="$TEMP_ROOT/kotlin"

echo "Cloning JetBrains/kotlin $UPSTREAM_REF into a temporary directory..."
git clone --filter=tree:0 --no-checkout --depth 1 --branch "$UPSTREAM_REF" "$UPSTREAM_URL" "$UPSTREAM_DIR" >/dev/null
resolved_revision="$(git -C "$UPSTREAM_DIR" rev-parse HEAD)"
if [[ "$resolved_revision" != "$UPSTREAM_REVISION" ]]; then
  echo "Pinned revision mismatch: expected $UPSTREAM_REVISION, got $resolved_revision" >&2
  exit 1
fi

failures=0
while IFS=$'\t' read -r record_id kind upstream_path fixture_path expected availability sha256 rationale; do
  [[ -z "$record_id" || "${record_id#\#}" != "$record_id" ]] && continue
  [[ -n "$upstream_path" && -n "$fixture_path" && -n "$sha256" ]] || {
    echo "Malformed manifest row: $record_id" >&2
    failures=$((failures + 1))
    continue
  }

  if ! git -C "$UPSTREAM_DIR" cat-file -e "${UPSTREAM_REVISION}:${upstream_path}"; then
    echo "Missing upstream path for $record_id: $upstream_path" >&2
    failures=$((failures + 1))
    continue
  fi

  upstream_sha256="$(hash_upstream_file "$UPSTREAM_DIR" "$upstream_path")"
  if [[ "$upstream_sha256" != "$sha256" ]]; then
    echo "Manifest hash mismatch for $record_id: expected $sha256, got $upstream_sha256" >&2
    failures=$((failures + 1))
    continue
  fi

  destination="$ROOT_DIR/$fixture_path"
  if [[ $DRY_RUN -eq 1 ]]; then
    if [[ -f "$destination" ]]; then
      actual_sha256="$(hash_file "$destination")"
      if [[ "$actual_sha256" != "$sha256" ]]; then
        echo "Fixture hash mismatch for $record_id: $destination" >&2
        failures=$((failures + 1))
        continue
      fi
      echo "VERIFY $record_id $fixture_path sha256=$sha256"
    else
      if [[ $VERIFY_ONLY -eq 1 ]]; then
        echo "Missing fixture for $record_id: $destination" >&2
        failures=$((failures + 1))
      else
        echo "DRY-RUN $record_id $fixture_path sha256=$sha256"
      fi
    fi
    continue
  fi

  if [[ -f "$destination" ]]; then
    actual_sha256="$(hash_file "$destination")"
    if [[ "$actual_sha256" != "$sha256" ]]; then
      echo "Refusing to overwrite non-matching fixture: $destination" >&2
      failures=$((failures + 1))
    else
      echo "UNCHANGED $record_id $fixture_path"
    fi
    continue
  fi

  mkdir -p "$(dirname "$destination")"
  git -C "$UPSTREAM_DIR" show "${UPSTREAM_REVISION}:${upstream_path}" >"$destination"
  if [[ "$(hash_file "$destination")" != "$sha256" ]]; then
    echo "Imported fixture hash verification failed: $destination" >&2
    failures=$((failures + 1))
  else
    echo "IMPORTED $record_id $fixture_path"
  fi
done < "$MANIFEST"

if [[ $failures -ne 0 ]]; then
  echo "ARCH-025 import failed with $failures issue(s)." >&2
  exit 1
fi

echo "ARCH-025 import verification succeeded at $UPSTREAM_REVISION."
