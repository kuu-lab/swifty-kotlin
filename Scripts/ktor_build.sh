#!/usr/bin/env bash
set -euo pipefail

# Compiles pinned snapshots of Ktor's core modules (and their kotlinx-io
# dependency) with kswiftc to track how close this compiler is to building
# real-world Kotlin Multiplatform code. Fetches sources into a cache dir
# outside the repo (git is not vendored), re-points a warm cache checkout to
# the requested KTOR_TAG / KOTLINX_IO_TAG before compiling (failing loudly
# instead of compiling stale sources when the revision cannot be fetched),
# compiles each module with
# `--emit library`, and writes a TSV of diagnostic-code counts per module.
#
# This is a diagnostic probe, not a golden/regression test: it does not run
# kotlinc, is not wired into CI, and a module failing to compile is expected.
# Re-run this after compiler changes to see whether the diagnostic counts shrank.
#
# Usage:
#   bash Scripts/ktor_build.sh                  # fetch + compile all modules
#   bash Scripts/ktor_build.sh --no-fetch        # reuse an existing cache
#   bash Scripts/ktor_build.sh --module ktor_io  # compile a single module

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KSWIFTC="${KSWIFTC:-$ROOT_DIR/.build/debug/kswiftc}"
# Space-separated flags appended to each kswiftc invocation, e.g.
# KSWIFTC_FLAGS="--stdlib-library /path/to/KSwiftKStdlib.kklib" to bypass the
# shared machine-wide stdlib cache under ~/Library/Caches/kswiftk/stdlib/,
# which can be stale or mid-write from another concurrent session.
KSWIFTC_FLAGS="${KSWIFTC_FLAGS:-}"
KSWIFTC_EXTRA_ARGS=()
if [[ -n "$KSWIFTC_FLAGS" ]]; then
  read -r -a KSWIFTC_EXTRA_ARGS <<< "$KSWIFTC_FLAGS"
fi
CACHE_DIR="${KTOR_BUILD_CACHE_DIR:-$ROOT_DIR/.ktor-build-cache}"
OUT_DIR="${KTOR_BUILD_OUT_DIR:-$ROOT_DIR/.ktor-build-out}"
KTOR_TAG="${KTOR_TAG:-3.6.0}"
KOTLINX_IO_TAG="${KOTLINX_IO_TAG:-0.9.1}"
DO_FETCH=1
ONLY_MODULE=""
# Set when a cache checkout is created or re-pointed; module artifacts from
# previous revisions are then dropped before compiling.
CACHE_REVISIONS_CHANGED=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-fetch) DO_FETCH=0; shift ;;
    --module) ONLY_MODULE="$2"; shift 2 ;;
    -h|--help)
      cat <<USAGE
Usage: $(basename "$0") [--no-fetch] [--module <name>]

Options:
  --no-fetch          Reuse the existing $CACHE_DIR checkout instead of cloning.
  --module <name>     Compile only this module (kotlinx_io|ktor_io|ktor_utils|ktor_http).
  -h, --help          Show this help.

Environment overrides: KSWIFTC, KTOR_BUILD_CACHE_DIR, KTOR_BUILD_OUT_DIR,
KTOR_TAG, KOTLINX_IO_TAG.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Module name -> source roots (space-separated, relative to $CACHE_DIR).
module_sources() {
  case "$1" in
    kotlinx_io) echo "kotlinx-io/core/common/src kotlinx-io/bytestring/common/src" ;;
    ktor_io) echo "ktor/ktor-io/common/src" ;;
    ktor_utils) echo "ktor/ktor-utils/common/src" ;;
    ktor_http) echo "ktor/ktor-http/common/src" ;;
    *) echo "" ;;
  esac
}

# Module name -> module dependencies (space-separated). A dependency is wired
# with `-I <dep>.kklib` when its artifact from a previous module compile exists
# in $OUT_DIR, so single-module runs degrade gracefully to the unresolved
# imports the module would see without its dependencies.
# kotlinx_io is intentionally not linked into downstream modules: the bundled
# stdlib now provides kotlinx.io.* and takes ownership over an explicitly
# imported upstream module (KSWIFTK-LIB-0031), which breaks resolution.
module_deps() {
  case "$1" in
    kotlinx_io) echo "" ;;
    ktor_io) echo "" ;;
    ktor_utils) echo "ktor_io" ;;
    ktor_http) echo "ktor_io ktor_utils" ;;
    *) echo "" ;;
  esac
}

if [[ ! -x "$KSWIFTC" ]]; then
  echo "kswiftc not found at $KSWIFTC. Run 'swift build' first." >&2
  exit 1
fi

# An unknown module name is rejected before the cache or the shared output
# dir's artifacts are touched.
if [[ -n "$ONLY_MODULE" && -z "$(module_sources "$ONLY_MODULE")" ]]; then
  echo "Unknown module: $ONLY_MODULE" >&2
  exit 1
fi

mkdir -p "$CACHE_DIR" "$OUT_DIR"

# Prints the exact tag of the commit checked out in $1, or nothing when HEAD
# is not exactly at a tag. Display only: several tags can name the same
# commit, so matching uses commit IDs instead.
checked_out_tag() {
  git -C "$1" describe --tags --exact-match HEAD 2>/dev/null || true
}

# Returns 0 when HEAD in $1 is already the commit the requested revision
# resolves to locally — via its tag, local branch, or origin/* branch — so
# several tags, or a previously fetched branch, on one commit all count.
cached_revision_matches() {
  local dest="$1" ref="$2" head candidate sha
  head="$(git -C "$dest" rev-parse HEAD)"
  for candidate in "refs/tags/$ref" "refs/heads/$ref" "refs/remotes/origin/$ref"; do
    sha="$(git -C "$dest" rev-parse --verify --quiet "$candidate^{commit}" 2>/dev/null || true)"
    if [[ -n "$sha" && "$sha" == "$head" ]]; then
      return 0
    fi
  done
  return 1
}

# Re-points an existing cache checkout at the requested revision instead of
# silently compiling whatever was fetched earlier. The fast path applies to
# pinned tags only: a local tag ref pointing at HEAD's commit needs no
# network, so offline warm-cache runs keep working and several tags on one
# commit all match. Branch requests are moving targets and always re-fetch
# when possible. On a mismatch the checkout is only switched when it is
# clean; if the requested revision cannot be fetched (offline or unknown
# ref), a warm cache already at that revision is still accepted and anything
# else fails, leaving the cached checkout untouched.
ensure_cached_revision() {
  local url="$1" tag="$2" dest="$3"
  local current head tag_sha fetched_ref
  current="$(checked_out_tag "$dest")"
  head="$(git -C "$dest" rev-parse HEAD)"
  tag_sha="$(git -C "$dest" rev-parse --verify --quiet "refs/tags/$tag^{commit}" 2>/dev/null || true)"
  if [[ -n "$tag_sha" && "$tag_sha" == "$head" ]]; then
    return 0
  fi
  if [[ -n "$(git -C "$dest" status --porcelain)" ]]; then
    echo "ktor_build: error: $dest has local changes; refusing to switch from '${current:-<no tag>}' to '$tag'." >&2
    echo "ktor_build:       commit or stash them, or point KTOR_BUILD_CACHE_DIR at a different directory." >&2
    return 1
  fi
  # Branches are tried before tags: version tags never share a name with a
  # branch, while a same-named tag published later must not hijack tracking
  # of the branch the request actually meant.
  fetched_ref=""
  if git -C "$dest" fetch --depth 1 origin "+refs/heads/$tag:refs/remotes/origin/$tag" 2>/dev/null; then
    fetched_ref="origin/$tag"
  elif git -C "$dest" fetch --depth 1 origin "+refs/tags/$tag:refs/tags/$tag" 2>/dev/null; then
    fetched_ref="$tag"
  fi
  if [[ -z "$fetched_ref" ]]; then
    if cached_revision_matches "$dest" "$tag"; then
      return 0
    fi
    echo "ktor_build: error: cannot fetch '$tag' from $url (offline or unknown ref?)." >&2
    echo "ktor_build:       cache left at '${current:-<no tag>}'; refusing to compile it as '$tag'." >&2
    return 1
  fi
  if ! git -C "$dest" checkout -q --detach "$fetched_ref"; then
    echo "ktor_build: error: failed to check out '$tag' in $dest; cache left at '${current:-<no tag>}'." >&2
    return 1
  fi
  # Branch requests re-fetch on every online run; when the remote has not
  # moved the checkout lands on the same commit and the compiled artifacts
  # are still valid, so only an actual revision change invalidates them.
  if [[ "$(git -C "$dest" rev-parse HEAD)" != "$head" ]]; then
    CACHE_REVISIONS_CHANGED=1
    echo "ktor_build: updated cache $dest: '${current:-<no tag>}' -> '$tag'." >&2
  fi
}

clone_sparse() {
  local url="$1" tag="$2" dest="$3" paths="$4"
  if [[ -d "$dest/.git" ]]; then
    ensure_cached_revision "$url" "$tag" "$dest"
    return
  fi
  git clone --depth 1 --filter=blob:none --sparse -b "$tag" "$url" "$dest"
  ( cd "$dest" && git sparse-checkout set $paths )
  CACHE_REVISIONS_CHANGED=1
}

if [[ "$DO_FETCH" -eq 1 ]]; then
  clone_sparse https://github.com/Kotlin/kotlinx-io "$KOTLINX_IO_TAG" \
    "$CACHE_DIR/kotlinx-io" "core bytestring"
  clone_sparse https://github.com/ktorio/ktor "$KTOR_TAG" \
    "$CACHE_DIR/ktor" "ktor-io ktor-utils ktor-http"
fi

# Single-module runs link dependency .kklib artifacts from $OUT_DIR, so those
# artifacts must come from the same sources this run compiles. $OUT_DIR may be
# shared across different KTOR_BUILD_CACHE_DIR checkouts, so record the source
# revisions the artifacts belong to and drop anything compiled from other
# sources instead of mixing revisions in the diagnostic results.
ktorn_io_head="$(git -C "$CACHE_DIR/kotlinx-io" rev-parse HEAD 2>/dev/null || true)"
ktor_head="$(git -C "$CACHE_DIR/ktor" rev-parse HEAD 2>/dev/null || true)"
if [[ -n "$ktorn_io_head" && -n "$ktor_head" ]]; then
  source_stamp="$OUT_DIR/.source-commits"
  current_stamp="$(cat "$source_stamp" 2>/dev/null || true)"
  new_stamp="$ktorn_io_head $ktor_head"
  if [[ "$CACHE_REVISIONS_CHANGED" -eq 1 || "$current_stamp" != "$new_stamp" ]]; then
    rm -rf "$OUT_DIR"/*.kklib
  fi
  printf '%s\n' "$new_stamp" > "$source_stamp"
fi

# Compile in dependency order unless a single module was requested.
MODULES="kotlinx_io ktor_io ktor_utils ktor_http"
if [[ -n "$ONLY_MODULE" ]]; then
  MODULES="$ONLY_MODULE"
fi

TSV="$OUT_DIR/summary.tsv"
echo -e "module\texit_code\tfile_count\terror_count\twarning_count\ttop_codes" > "$TSV"

for module in $MODULES; do
  roots="$(module_sources "$module")"
  if [[ -z "$roots" ]]; then
    echo "Unknown module: $module" >&2
    exit 1
  fi
  files=()
  for root in $roots; do
    while IFS= read -r f; do files+=("$f"); done < <(find "$CACHE_DIR/$root" -name '*.kt' | sort)
  done
  log="$OUT_DIR/$module.log"
  kklib="$OUT_DIR/$module.kklib"
  rm -rf "$kklib"
  dep_args=()
  for dep in $(module_deps "$module"); do
    if [[ -d "$OUT_DIR/$dep.kklib" ]]; then
      dep_args+=("-I" "$OUT_DIR/$dep.kklib")
    fi
  done
  set +e
  "$KSWIFTC" --emit library -m "$module" -o "$kklib" "${dep_args[@]}" "${KSWIFTC_EXTRA_ARGS[@]}" "${files[@]}" > "$log" 2>&1
  exit_code=$?
  set -e
  error_count=$(grep -c 'error KSWIFTK' "$log" || true)
  warning_count=$(grep -c 'warning KSWIFTK' "$log" || true)
  top_codes=$(grep -o 'KSWIFTK-[A-Z]*-[0-9A-Z]*' "$log" | sort | uniq -c | sort -rn | head -5 \
    | awk '{printf "%s:%s;", $2, $1}' || true)
  echo -e "$module\t$exit_code\t${#files[@]}\t$error_count\t$warning_count\t$top_codes" >> "$TSV"
  echo "== $module: exit=$exit_code files=${#files[@]} errors=$error_count warnings=$warning_count =="
done

echo
echo "Summary written to $TSV"
column -t -s $'\t' "$TSV"
