#!/usr/bin/env bash
# Regression test for ktor_build.sh cache revision handling.
#
# The probe sparse-clones pinned snapshots of Ktor / kotlinx-io into a cache
# dir. Changing KTOR_TAG / KOTLINX_IO_TAG with a warm cache used to silently
# compile the previously fetched revision. This test uses local file://
# "remotes" (the probe's hardcoded GitHub URLs are rewritten with
# url.insteadOf in a throwaway GIT_CONFIG_GLOBAL) and a stub kswiftc, so it
# needs no network and no compiler build.
#
# Covered behavior:
#   1. cold fetch checks out the requested tag
#   2. warm cache + changed KTOR_TAG re-points the checkout and compiles the
#      requested revision's sources
#   3. warm cache matching the requested tag works with remotes unreachable
#      (offline fast path, no fetch attempted)
#   4. warm cache mismatch + unreachable remote fails loudly and leaves the
#      cached checkout untouched
#   5. --no-fetch keeps its explicit "reuse whatever is cached" semantics
#   6. a dirty cache refuses to switch revisions, preserving local changes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROBE="$SCRIPT_DIR/ktor_build.sh"

if ! command -v git >/dev/null 2>&1; then
  echo "FAIL: git is required" >&2
  exit 1
fi
if [[ ! -f "$PROBE" ]]; then
  echo "FAIL: $PROBE not found" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-ktor-revision.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
FIX="$TEMP_DIR/fixture"
mkdir -p "$FIX/remotes" "$FIX/bin"

export GIT_CONFIG_GLOBAL="$FIX/gitconfig"
cat > "$GIT_CONFIG_GLOBAL" <<EOF
[user]
	name = Ktor Probe Test
	email = ktor-probe@example.com
[url "file://$FIX/remotes/ktor.git"]
	insteadOf = https://github.com/ktorio/ktor
[url "file://$FIX/remotes/kotlinx-io.git"]
	insteadOf = https://github.com/Kotlin/kotlinx-io
[uploadpack]
	allowFilter = true
EOF

# ktor fixture: tags 1.0.0 and 2.0.0; only ktor-io/common/src differs by a
# marker file so the stub kswiftc's recorded arguments show which revision
# was actually compiled.
mkdir -p "$FIX/work-ktor"
cd "$FIX/work-ktor"
git init -q -b master
mkdir -p ktor-io/common/src ktor-utils/common/src ktor-http/common/src
cat > ktor-io/common/src/Common.kt <<'EOF'
package ktor.io
fun ktorProbeCommon(): Int = 0
EOF
cat > ktor-io/common/src/V1Only.kt <<'EOF'
package ktor.io
fun ktorProbeMarkerV1(): Int = 1
EOF
cat > ktor-utils/common/src/Utils.kt <<'EOF'
package ktor.utils
fun ktorProbeUtils(): Int = 2
EOF
cat > ktor-http/common/src/Http.kt <<'EOF'
package ktor.http
fun ktorProbeHttp(): Int = 3
EOF
git add -A
git commit -qm "ktor fixture v1"
git tag 1.0.0
git rm -q ktor-io/common/src/V1Only.kt
cat > ktor-io/common/src/V2Only.kt <<'EOF'
package ktor.io
fun ktorProbeMarkerV2(): Int = 2
EOF
git add -A
git commit -qm "ktor fixture v2"
git tag 2.0.0
git clone -q --bare "$FIX/work-ktor" "$FIX/remotes/ktor.git"

# kotlinx-io fixture: single tag 0.1.0 (same revision-sync code path).
mkdir -p "$FIX/work-kotlinx-io"
cd "$FIX/work-kotlinx-io"
git init -q -b master
mkdir -p core/common/src bytestring/common/src
cat > core/common/src/Io.kt <<'EOF'
package kotlinx.io
fun ioProbeMarker(): Int = 4
EOF
cat > bytestring/common/src/Bs.kt <<'EOF'
package kotlinx.io.bytestring
fun bsProbeMarker(): Int = 5
EOF
git add -A
git commit -qm "kotlinx-io fixture"
git tag 0.1.0
git clone -q --bare "$FIX/work-kotlinx-io" "$FIX/remotes/kotlinx-io.git"

# Stub kswiftc: records its arguments (one line per invocation) and creates
# the -o output directory so downstream module dependency wiring stays happy.
cat > "$FIX/bin/kswiftc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${KSWIFTC_STUB_LOG:?KSWIFTC_STUB_LOG must be set}"
out=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-o" ]]; then out="$arg"; fi
  prev="$arg"
done
if [[ -n "$out" ]]; then mkdir -p "$out"; fi
exit 0
EOF
chmod +x "$FIX/bin/kswiftc"

CACHE_DIR="$FIX/cache"
OUT_DIR="$FIX/out"
STUB_LOG="$FIX/kswiftc.log"
KTOR_TAG="1.0.0"
KOTLINX_IO_TAG="0.1.0"
PROBE_LOG="$TEMP_DIR/probe.log"
PROBE_EXIT=0

probe() {
  : > "$STUB_LOG"
  set +e
  env KTOR_TAG="$KTOR_TAG" KOTLINX_IO_TAG="$KOTLINX_IO_TAG" \
    KTOR_BUILD_CACHE_DIR="$CACHE_DIR" KTOR_BUILD_OUT_DIR="$OUT_DIR" \
    KSWIFTC="$FIX/bin/kswiftc" KSWIFTC_STUB_LOG="$STUB_LOG" \
    GIT_CONFIG_GLOBAL="$GIT_CONFIG_GLOBAL" \
    bash "$PROBE" "$@" >"$PROBE_LOG" 2>&1
  PROBE_EXIT=$?
  set -e
}

cache_tag() {
  git -C "$CACHE_DIR/ktor" describe --tags --exact-match HEAD 2>/dev/null || true
}

fail() {
  echo "FAIL: $*" >&2
  echo "--- probe output ---" >&2
  cat "$PROBE_LOG" >&2 || true
  exit 1
}

expect_success() {
  if [[ "$PROBE_EXIT" -ne 0 ]]; then
    fail "expected probe success (exit 0), got $PROBE_EXIT: $1"
  fi
}

expect_failure() {
  if [[ "$PROBE_EXIT" -eq 0 ]]; then
    fail "expected probe failure, got exit 0: $1"
  fi
}

# 1. Cold fetch checks out the requested tag.
probe --module ktor_io
expect_success "cold fetch of KTOR_TAG=$KTOR_TAG"
[[ "$(cache_tag)" == "1.0.0" ]] || fail "cold fetch left cache at '$(cache_tag)', expected 1.0.0"
grep -q 'V1Only.kt' "$STUB_LOG" || fail "cold fetch did not compile 1.0.0 sources"
echo "ok: cold fetch checks out the requested tag"

# 2. Warm cache + changed KTOR_TAG re-points the checkout and compiles the
#    requested revision's sources (the regression: this used to silently
#    compile 1.0.0 while reporting success for a 2.0.0 request).
KTOR_TAG="2.0.0"
probe --module ktor_io
expect_success "warm-cache run with KTOR_TAG=2.0.0"
[[ "$(cache_tag)" == "2.0.0" ]] || fail "warm cache stayed at '$(cache_tag)', expected 2.0.0"
grep -q 'V2Only.kt' "$STUB_LOG" || fail "requested 2.0.0 but compiled sources lack V2Only.kt"
if grep -q 'V1Only.kt' "$STUB_LOG"; then
  fail "requested 2.0.0 but compiled sources still contain V1Only.kt"
fi
echo "ok: warm cache syncs to the requested tag and compiles its sources"

# 3. Warm cache matching the requested tag works with remotes unreachable.
mv "$FIX/remotes" "$FIX/remotes.hidden"
probe --module ktor_io
expect_success "offline run with matching cache"
[[ "$(cache_tag)" == "2.0.0" ]] || fail "offline run changed cache to '$(cache_tag)'"
mv "$FIX/remotes.hidden" "$FIX/remotes"
echo "ok: matching warm cache works offline"

# 4. Warm cache mismatch + unreachable remote fails loudly, cache untouched.
KTOR_TAG="1.0.0"
mv "$FIX/remotes" "$FIX/remotes.hidden"
probe --module ktor_io
expect_failure "offline run with mismatched cache"
grep -q '1\.0\.0' "$PROBE_LOG" || fail "failure output does not name requested tag 1.0.0"
grep -q '2\.0\.0' "$PROBE_LOG" || fail "failure output does not name cached tag 2.0.0"
[[ "$(cache_tag)" == "2.0.0" ]] || fail "failed run changed cache to '$(cache_tag)'"
mv "$FIX/remotes.hidden" "$FIX/remotes"
echo "ok: unfetchable revision fails loudly and leaves the cache untouched"

# 5. --no-fetch keeps its explicit reuse semantics: no sync, exit 0.
KTOR_TAG="1.0.0"
probe --no-fetch --module ktor_io
expect_success "--no-fetch with warm cache"
[[ "$(cache_tag)" == "2.0.0" ]] || fail "--no-fetch changed cache to '$(cache_tag)'"
echo "ok: --no-fetch reuses the cached checkout as documented"

# 6. A dirty cache refuses to switch revisions, preserving local changes.
printf '\n// local probe edit\n' >> "$CACHE_DIR/ktor/ktor-io/common/src/V2Only.kt"
KTOR_TAG="1.0.0"
probe --module ktor_io
expect_failure "dirty cache with mismatched tag"
grep -q 'local changes' "$PROBE_LOG" || fail "dirty-cache failure does not mention local changes"
grep -q 'local probe edit' "$CACHE_DIR/ktor/ktor-io/common/src/V2Only.kt" \
  || fail "local edit in cache was lost"
[[ "$(cache_tag)" == "2.0.0" ]] || fail "dirty-cache run changed cache to '$(cache_tag)'"
echo "ok: dirty cache refuses to switch and preserves local changes"

echo "PASS: ktor_build.sh honors requested revisions with a warm cache"
