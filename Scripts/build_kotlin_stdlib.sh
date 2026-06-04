#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KSWIFTC="${KSWIFTC:-"$ROOT_DIR/.build/debug/kswiftc"}"
OUTPUT_BASE="${1:-"$ROOT_DIR/.build/debug/kotlin-stdlib"}"
STDLIB_DIR="$ROOT_DIR/Stdlib"

if [[ ! -x "$KSWIFTC" ]]; then
  swift build --product kswiftc
fi

mkdir -p "$(dirname "$OUTPUT_BASE")"

sources=()
while IFS= read -r -d '' source; do
  sources+=("$source")
done < <(find "$STDLIB_DIR" -name '*.kt' -print0 | sort -z)

if [[ ${#sources[@]} -eq 0 ]]; then
  echo "No Kotlin stdlib sources found under $STDLIB_DIR" >&2
  exit 1
fi

"$KSWIFTC" \
  --no-stdlib \
  --emit library \
  -m KotlinStdlib \
  -o "$OUTPUT_BASE" \
  "${sources[@]}"

echo "$OUTPUT_BASE.kklib"
