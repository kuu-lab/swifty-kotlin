# Shared shell helpers for Scripts/*.sh

[[ -n "${_KSWIFTK_SCRIPTS_COMMON_SH:-}" ]] && return 0
_KSWIFTK_SCRIPTS_COMMON_SH=1

# Scripts sourcing this file rely on bash >= 4 features (associative arrays,
# mapfile). macOS ships bash 3.2 at /bin/bash; the `#!/usr/bin/env bash`
# shebangs pick up a newer bash from PATH (e.g. Homebrew's).
if (( BASH_VERSINFO[0] < 4 )); then
    echo "Scripts/*.sh require bash >= 4 (found $BASH_VERSION; on macOS: brew install bash)" >&2
    exit 1
fi

# Canonical golden-update command, shown in failure hints. The -swift-version
# flags match the CI (Full Swift Tests) language mode; keep in sync with the
# "Golden update workflow" section of Scripts/README.md.
GOLDEN_UPDATE_CMD="UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6"

# Map a diff case path to its artifact directory name: basename, drop the .kt
# extension, replace anything outside [A-Za-z0-9._-]. diff_kotlinc.sh writes
# failure artifacts under this name and diff_kotlinc_ci_summary.sh resolves
# them back from case paths, so both sides must share this exact mapping.
sanitize_case_name() {
    local input="$1"
    input="${input##*/}"
    input="${input%.kt}"
    input="${input//[^A-Za-z0-9._-]/_}"
    printf '%s' "$input"
}

# Interleaved shard selection over stdin lines: line i (0-based) passes only
# when i % count == index. count=1 passes every line. Both diff_kotlinc.sh and
# shard_swift_tests.sh stripe work across CI runners with this rule; changing
# it in one place but not the other would silently unbalance the shards.
shard_interleave() {
    local index="$1"
    local count="$2"
    awk -v idx="$index" -v cnt="$count" '(NR - 1) % cnt == idx'
}

# Join stdin lines into "a|b|c" regex alternations of at most $1 items,
# one alternation per output line. Used to keep each --filter argument below
# per-argument exec() limits (Linux MAX_ARG_STRLEN is ~128KB).
chunk_alternations() {
    awk -v size="$1" '
        { buf = (len == 0) ? $0 : buf "|" $0; len++ }
        len >= size { print buf; buf = ""; len = 0 }
        END { if (len > 0) print buf }
    '
}

# --- kotlinc-vs-kswiftc diff preflight/skip helpers --------------------
# Shared by diff_kotlinc.sh and diff_diagnostics.sh so the skip-directive,
# KOTLINC_FLAGS extraction, and JDK/timeout preflight checks can't drift
# between the two diff runners.

# True (grep match, so callers use it directly in an if) when $1 carries a
# `// KSWIFTK_DIFF_IGNORE` or `// SKIP-DIFF` directive, unless the caller's
# FORCE_RUN_SKIPPED=1 overrides skipping.
should_skip_case() {
    local kt_file="$1"
    if [[ $FORCE_RUN_SKIPPED -eq 1 ]]; then
        return 1
    fi
    grep -Eq '^[[:space:]]*//[[:space:]]*(KSWIFTK_DIFF_IGNORE|SKIP-DIFF)\b' "$kt_file"
}

# Extract extra kotlinc flags from `// KOTLINC_FLAGS: <flags>` directives in
# the test file, joined onto one line.
get_kotlinc_extra_flags() {
    local kt_file="$1"
    { grep -E '^[[:space:]]*//[[:space:]]*KOTLINC_FLAGS:' "$kt_file" 2>/dev/null || true; } \
        | sed 's/.*KOTLINC_FLAGS:[[:space:]]*//' | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

# Print the JDK major version reported by `$1 -version` (e.g. "17", "21");
# pre-JDK9 "1.x" version strings map to their historical major number x.
detect_java_major_version() {
    local java_bin="$1"
    "$java_bin" -version 2>&1 \
        | awk -F'"' '/version/ { print $2; exit }' \
        | awk -F'[.]' '{ print ($1 == "1") ? $2 : $1 }'
}

# Exit 1 unless $1 (a java binary) reports JDK 21+, honoring the caller's
# DIFF_REQUIRE_JDK21=0 to bypass the check entirely. The reference outputs
# depend on the JDK version: Double/Float.toString() only emits the shortest
# round-trip form from JDK 19 onwards (JDK-4511638); older JDKs print extra
# digits (e.g. 1.23456792E8 instead of 1.2345679E8), producing spurious FAILs
# against kswiftc. CI pins java-version 21.
# $2 names the gate in the error message (e.g. "diff gate",
# "diagnostic diff gate"); any further args print as extra hint lines above
# the common "set JAVA_BIN/JAVA_HOME..." remediation line.
require_jdk21_or_exit() {
    local java_bin="$1" gate_label="$2"
    shift 2
    if [[ "${DIFF_REQUIRE_JDK21:-1}" == "0" ]]; then
        return 0
    fi
    local java_major
    java_major="$(detect_java_major_version "$java_bin")"
    if [[ ! "$java_major" =~ ^[0-9]+$ ]] || (( java_major < 21 )); then
        echo "java is too old for the $gate_label: $java_bin reports major version '${java_major:-unknown}', need >= 21." >&2
        local hint
        for hint in "$@"; do
            echo "$hint" >&2
        done
        echo "Set JAVA_BIN/JAVA_HOME to a JDK 21+, or DIFF_REQUIRE_JDK21=0 to bypass." >&2
        exit 1
    fi
}

# Exit 1 if $1 (a `timeout` command name/path) is not resolvable on PATH.
require_timeout_cmd_or_exit() {
    local timeout_cmd="$1"
    if ! command -v "$timeout_cmd" >/dev/null 2>&1; then
        echo "timeout command not found: $timeout_cmd (on macOS: brew install coreutils, or set TIMEOUT)" >&2
        exit 1
    fi
}

detect_workers() {
    local detected

    # Linux: use nproc if available.
    if detected="$(nproc 2>/dev/null)" \
        && [[ "$detected" =~ ^[0-9]+$ ]] \
        && (( detected > 0 )); then
        printf "%s" "$detected"
        return
    fi

    # macOS: use logical cores by default to maximize XCTest worker concurrency.
    if detected="$(sysctl -n hw.logicalcpu 2>/dev/null)" \
        && [[ "$detected" =~ ^[0-9]+$ ]] \
        && (( detected > 0 )); then
        printf "%s" "$detected"
        return
    fi

    if detected="$(sysctl -n hw.physicalcpu 2>/dev/null)" \
        && [[ "$detected" =~ ^[0-9]+$ ]] \
        && (( detected > 0 )); then
        printf "%s" "$detected"
        return
    fi

    printf ""
}

# Append Swift 6.3+ compilation-caching flags to the named bash array when
# SWIFT_ENABLE_COMPILE_CACHE is set. Both the build step and the test step must
# pass identical -Xswiftc flags to avoid invalidating SwiftPM's incremental cache.
kswiftk_append_compile_cache_flags() {
    local -n __flags_array="$1"
    if [[ "${SWIFT_ENABLE_COMPILE_CACHE:-}" == "1" ]]; then
        local cas_path="${SWIFT_CAS_PATH:-${TMPDIR:-/tmp}/swift-cas}"
        # swift-driver silently disables caching unless the build also uses
        # explicit modules ("warning: -cache-compile-job cannot be used without
        # explicit module build, turn off caching").
        __flags_array+=(-Xswiftc -explicit-module-build)
        __flags_array+=(-Xswiftc -cache-compile-job)
        __flags_array+=(-Xswiftc -cas-path -Xswiftc "$cas_path")
    fi
    if [[ "${SWIFT_ENABLE_CACHE_REMARKS:-}" == "1" ]]; then
        __flags_array+=(-Xswiftc -Rcache-compile-job)
    fi
}

# For swiftbuild (the new Swift Build preview engine in Swift 6.3+), enable the
# integrated Swift/Clang compilation caches by setting the build-system defaults.
# This is a separate mechanism from the -Xswiftc -cache-compile-job flags used
# by the legacy native build system and must be set in the environment.
kswiftk_setup_compile_cache_env() {
    if [[ "${SWIFT_ENABLE_COMPILE_CACHE:-}" == "1" ]]; then
        if [[ "${SWIFT_BUILD_SYSTEM:-}" == "swiftbuild" ]]; then
            export EnableSwiftCachingByDefault=true
            export EnableClangCachingByDefault=true
            export EnableSwiftExplicitModulesByDefault=true
        fi
    fi
}
