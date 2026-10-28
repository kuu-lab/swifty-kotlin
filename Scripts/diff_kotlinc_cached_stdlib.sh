# Optional, compiler-validated stdlib reuse for diff and candidate-only runs.
# Sourced by the callers after their paths and timeout settings are resolved.

[[ -n "${_KSWIFTK_DIFF_CACHED_STDLIB_SH:-}" ]] && return 0
_KSWIFTK_DIFF_CACHED_STDLIB_SH=1

configure_diff_compiler_process() {
  # A global daemon may belong to another worktree/compiler. Keep the cache
  # resolver and case compilations on this exact executable by default.
  if [[ "${DIFF_USE_DAEMON:-0}" != 1 ]]; then
    export KSWIFTK_DAEMON_SOCKET="/dev/null/kswiftk-diff-no-daemon"
  fi
}

resolve_cached_diff_stdlib() {
  # An opted-in daemon may execute another compiler; its identity cannot be
  # established by a local --cached-stdlib-path invocation.
  [[ -z "${DIFF_STDLIB_LIBRARY:-}" && "${DIFF_REUSE_STDLIB_CACHE:-1}" != 0 \
     && "${DIFF_USE_DAEMON:-0}" != 1 ]] || return 0
  local help
  # Older compilers and external wrappers may not implement this protocol.
  if ! help="$("$KSWIFTC" --help 2>/dev/null)" || [[ "$help" != *--cached-stdlib-path* ]]; then
    return 0
  fi
  local output errors
  output="$(mktemp "${TMPDIR:-/tmp}/kswiftk-diff-stdlib-out.XXXXXX")" || return 1
  errors="$(mktemp "${TMPDIR:-/tmp}/kswiftk-diff-stdlib-err.XXXXXX")" || { rm -f "$output"; return 1; }
  local timeout="${STDLIB_COMPILE_TIMEOUT:-${DIFF_STDLIB_COMPILE_TIMEOUT:-600}}"
  local status=0 path
  echo "Resolving validated stdlib artifact cache"
  "$TIMEOUT_CMD" "$timeout" "$KSWIFTC" --cached-stdlib-path >"$output" 2>"$errors" || status=$?
  if [[ "$status" -eq 2 ]]; then
    echo "Stdlib cache identity unavailable; building a fresh artifact." >&2
    [[ ! -s "$errors" ]] || cat "$errors" >&2
    rm -f "$output" "$errors"
    return 0
  fi
  if [[ "$status" -ne 0 ]]; then
    if [[ "$status" -eq 124 ]]; then
      echo "Stdlib cache resolution timed out after ${timeout}s" >&2
    else
      echo "Stdlib cache resolution failed: exit=$status" >&2
    fi
    [[ ! -s "$errors" ]] || cat "$errors" >&2
    rm -f "$output" "$errors"
    return 1
  fi
  path="$(cat "$output")"
  rm -f "$output" "$errors"
  if [[ "$path" != /* || "$path" == *$'\n'* || ! -d "$path" || ! -f "$path/manifest.json" ]]; then
    echo "Stdlib cache returned an invalid artifact path" >&2
    return 1
  fi
  DIFF_STDLIB_LIBRARY="$path"
  echo "Using validated stdlib artifact: $path"
}
