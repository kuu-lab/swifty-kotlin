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
#   6. single-module runs drop dependency .kklib artifacts compiled from a
#      previous revision, but keep reusing fresh ones
#   7. several tags on one commit all match offline (compared by commit ID,
#      not by the single tag name `git describe` happens to return)
#   8. a branch request tracks remote advances when online, keeps its
#      artifacts when unchanged, and still compiles from the warm cache
#      offline
#   9. a tag published with the same name as the tracked branch does not
#      hijack branch requests
#  10. a dirty cache refuses to switch revisions, preserving local changes
#  11. switching KTOR_BUILD_CACHE_DIR with a shared output dir drops
#      dependency artifacts built from another revision
#  12. an unknown --module name fails before touching caches or artifacts
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
# A second tag on the very same commit: exercises commit-based matching when
# several tag names resolve to the checked-out HEAD.
git tag 1.0.1
git rm -q ktor-io/common/src/V1Only.kt
cat > ktor-io/common/src/V2Only.kt <<'EOF'
package ktor.io
fun ktorProbeMarkerV2(): Int = 2
EOF
git add -A
git commit -qm "ktor fixture v2"
git tag 2.0.0
# A moving branch at the v1 commit: branch requests must re-fetch online
# instead of matching a stale local ref forever.
git branch moving 1.0.0
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
    KTOR_BUILD_CACHE_DIR="${PROBE_CACHE_DIR:-$CACHE_DIR}" KTOR_BUILD_OUT_DIR="$OUT_DIR" \
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

# 6. Single-module runs never link dependency artifacts from a previous
#    revision: fresh artifacts are reused, stale ones are dropped on sync.
KTOR_TAG="2.0.0"
probe --module ktor_utils
expect_success "single-module run reusing a fresh dependency artifact"
grep -q 'ktor_io\.kklib' "$STUB_LOG" || fail "fresh dependency artifact was not linked"
[[ -d "$OUT_DIR/ktor_utils.kklib" ]] || fail "ktor_utils artifact missing after compile"

KTOR_TAG="1.0.0"
probe --module ktor_utils
expect_success "single-module run after a revision sync"
[[ "$(cache_tag)" == "1.0.0" ]] || fail "cache not synced to 1.0.0: '$(cache_tag)'"
if grep -q 'ktor_io\.kklib' "$STUB_LOG"; then
  fail "stale ktor_io.kklib from the previous revision was linked after the sync"
fi
[[ ! -e "$OUT_DIR/ktor_io.kklib" ]] || fail "stale ktor_io.kklib survived the revision sync"
[[ -d "$OUT_DIR/ktor_utils.kklib" ]] || fail "ktor_utils artifact missing after compile"
echo "ok: single-module runs drop stale dependency artifacts on revision sync"

# 7. Several tags on one commit all count as matching, also offline: the
#    requested revision is resolved to its commit and compared with HEAD,
#    not against the single tag name `git describe` returns for HEAD.
KTOR_TAG="1.0.1"
probe --module ktor_io
expect_success "online fetch of alias tag 1.0.1 on the cached commit"
head_commit="$(git -C "$CACHE_DIR/ktor" rev-parse HEAD)"

mv "$FIX/remotes" "$FIX/remotes.hidden"
KTOR_TAG="1.0.0"
probe --module ktor_io
expect_success "offline run requesting tag 1.0.0 on a multi-tag commit"
KTOR_TAG="1.0.1"
probe --module ktor_io
expect_success "offline run requesting tag 1.0.1 on a multi-tag commit"
mv "$FIX/remotes.hidden" "$FIX/remotes"
[[ "$(git -C "$CACHE_DIR/ktor" rev-parse HEAD)" == "$head_commit" ]] \
  || fail "offline multi-tag runs moved HEAD"
echo "ok: multi-tag commits match offline by commit, not by tag name"

# 8. A branch request tracks remote advances when online and still compiles
#    from the warm cache offline: branches are moving targets, so only tags
#    get the network-free fast path.
KTOR_TAG="moving"
probe --module ktor_io
expect_success "branch request re-points the warm cache"
[[ "$(git -C "$CACHE_DIR/ktor" rev-parse HEAD)" == \
  "$(git -C "$FIX/remotes/ktor.git" rev-parse refs/heads/moving)" ]] \
  || fail "branch checkout does not match the remote branch"

git -C "$FIX/work-ktor" checkout -q moving
printf '\n// branch advance\n' >> "$FIX/work-ktor/ktor-io/common/src/Common.kt"
git -C "$FIX/work-ktor" commit -qam "advance moving branch"
git -C "$FIX/work-ktor" push -q "$FIX/remotes/ktor.git" moving
probe --module ktor_io
expect_success "warm run tracks the advanced branch"
[[ "$(git -C "$CACHE_DIR/ktor" rev-parse HEAD)" == \
  "$(git -C "$FIX/remotes/ktor.git" rev-parse refs/heads/moving)" ]] \
  || fail "branch advance was not picked up"

# Re-running an unchanged branch re-fetches but lands on the same commit, so
# the compiled dependency artifacts must survive for single-module runs.
probe --module ktor_utils
expect_success "unchanged branch run keeps dependency artifacts"
grep -q 'ktor_io\.kklib' "$STUB_LOG" \
  || fail "unchanged branch run dropped the ktor_io.kklib dependency link"
[[ -d "$OUT_DIR/ktor_io.kklib" ]] || fail "ktor_io.kklib was deleted by an unchanged branch run"

mv "$FIX/remotes" "$FIX/remotes.hidden"
probe --module ktor_io
expect_success "offline run on a warm branch cache"
mv "$FIX/remotes.hidden" "$FIX/remotes"
echo "ok: branch requests track remote advances and work offline"

# 9. A tag published with the same name as the tracked branch must not
#    hijack branch requests: the branch keeps winning the fetch.
git -C "$FIX/remotes/ktor.git" tag moving \
  "$(git -C "$FIX/remotes/ktor.git" rev-parse '2.0.0^{commit}')"
KTOR_TAG="moving"
probe --module ktor_io
expect_success "branch request with a same-named tag published"
[[ "$(git -C "$CACHE_DIR/ktor" rev-parse HEAD)" == \
  "$(git -C "$FIX/remotes/ktor.git" rev-parse refs/heads/moving)" ]] \
  || fail "same-named tag hijacked the branch checkout"
echo "ok: a same-named tag does not hijack branch tracking"

# 10. A dirty cache refuses to switch revisions, preserving local changes.
head_before="$(git -C "$CACHE_DIR/ktor" rev-parse HEAD)"
printf '\n// local probe edit\n' >> "$CACHE_DIR/ktor/ktor-io/common/src/V1Only.kt"
KTOR_TAG="2.0.0"
probe --module ktor_io
expect_failure "dirty cache with mismatched tag"
grep -q 'local changes' "$PROBE_LOG" || fail "dirty-cache failure does not mention local changes"
grep -q 'local probe edit' "$CACHE_DIR/ktor/ktor-io/common/src/V1Only.kt" \
  || fail "local edit in cache was lost"
[[ "$(git -C "$CACHE_DIR/ktor" rev-parse HEAD)" == "$head_before" ]] \
  || fail "dirty-cache run moved HEAD"
echo "ok: dirty cache refuses to switch and preserves local changes"

# 11. Switching KTOR_BUILD_CACHE_DIR while sharing the output dir must not
#     keep dependency artifacts built from another revision: the output dir
#     records which source revisions produced its artifacts. Scenario 10 left
#     the cache dirty, so both cache dirs and the output dir start fresh.
CACHE_DIR2="$FIX/cache-b"
rm -rf "$CACHE_DIR" "$CACHE_DIR2" "$OUT_DIR"
KTOR_TAG="1.0.0"

# Cold clone of cache A builds ktor_io.kklib from the 1.0.0 sources.
probe --module ktor_io
expect_success "cache A cold run"
[[ -d "$OUT_DIR/ktor_io.kklib" ]] || fail "cache A did not produce ktor_io.kklib"

# A second cache at a different revision rebuilds the artifact from 2.0.0.
KTOR_TAG="2.0.0"
PROBE_CACHE_DIR="$CACHE_DIR2" probe --module ktor_io
expect_success "cache B cold run at 2.0.0"
[[ -d "$OUT_DIR/ktor_io.kklib" ]] || fail "cache B did not produce ktor_io.kklib"

# Back to the unchanged cache A request: no fetch moves its HEAD, but the
# artifact in the shared output dir came from 2.0.0 and must be dropped
# instead of being linked into the 1.0.0 compile of ktor_utils.
KTOR_TAG="1.0.0"
probe --module ktor_utils
expect_success "return to cache A at 1.0.0"
if grep -q 'ktor_io\.kklib' "$STUB_LOG"; then
  fail "shared output dir linked a ktor_io.kklib built from another revision"
fi
[[ ! -e "$OUT_DIR/ktor_io.kklib" ]] || fail "foreign-revision ktor_io.kklib survived the cache switch"
[[ -d "$OUT_DIR/ktor_utils.kklib" ]] || fail "ktor_utils artifact missing after compile"

# A full run rebuilds the dependency from the current sources, and a later
# single-module run reuses the matching artifact again.
probe
expect_success "full run rebuilding dependencies from cache A"
[[ -d "$OUT_DIR/ktor_io.kklib" ]] || fail "full run did not rebuild ktor_io.kklib"
probe --module ktor_utils
expect_success "single-module run after the full rebuild"
grep -q 'ktor_io\.kklib' "$STUB_LOG" \
  || fail "matching dependency artifact was not reused after the cache switch"
echo "ok: switching source caches drops foreign-revision artifacts"

# 12. An unknown --module name is rejected before the cache sync or the
#     shared output dir's artifact invalidation run: a typo must not delete
#     artifacts built from another revision's cache.
[[ -d "$OUT_DIR/ktor_io.kklib" ]] || fail "precondition: ktor_io.kklib missing"
KTOR_TAG="2.0.0"
PROBE_CACHE_DIR="$CACHE_DIR2" probe --module nope
expect_failure "unknown module name"
[[ -d "$OUT_DIR/ktor_io.kklib" ]] || fail "unknown-module run dropped shared artifacts"
[[ -d "$OUT_DIR/ktor_utils.kklib" ]] || fail "unknown-module run dropped shared artifacts"
KTOR_TAG="1.0.0"
probe --module ktor_utils
expect_success "single-module run after the rejected typo"
grep -q 'ktor_io\.kklib' "$STUB_LOG" \
  || fail "dependency artifact was not reused after the rejected typo"
echo "ok: unknown module names fail before touching caches or artifacts"

echo "PASS: ktor_build.sh honors requested revisions with a warm cache"
