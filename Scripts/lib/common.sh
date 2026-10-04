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

# Extract the major version number from `$1 -version` output (e.g. "21" from
# both "21.0.2" and legacy "1.8.0_392" schemes). Prints nothing (not even a
# newline) if the output cannot be parsed; callers must validate with a regex.
java_major_version() {
    local java_bin="$1"
    "$java_bin" -version 2>&1 \
        | awk -F'"' '/version/ { print $2; exit }' \
        | awk -F'[.]' '{ print ($1 == "1") ? $2 : $1 }'
}

# Verify kswiftc/kotlinc/java/timeout are present and, unless $5 is "0", that
# java reports major version >= 21 (JDK 21 is what CI pins; older JDKs format
# things like Double/Float.toString() differently and cause spurious diff
# FAILs). Exits the calling script with status 1 and an actionable message on
# any failure. $6 is a short label for the gate (used in the JDK message,
# e.g. "diff gate" / "diagnostic diff gate"); $7 is an optional extra hint
# line appended after the version-mismatch message.
require_diff_tooling() {
    local kswiftc="$1" kotlinc="$2" java_bin="$3" timeout_cmd="$4" require_jdk21="$5" gate_label="$6" extra_hint="${7:-}"

    if ! [[ -x "$kswiftc" ]]; then
        echo "kswiftc not found or not executable: $kswiftc" >&2
        exit 1
    fi
    if ! command -v "$kotlinc" >/dev/null 2>&1; then
        echo "kotlinc command not found: $kotlinc" >&2
        exit 1
    fi
    if ! command -v "$java_bin" >/dev/null 2>&1; then
        echo "java command not found: $java_bin" >&2
        exit 1
    fi
    if ! command -v "$timeout_cmd" >/dev/null 2>&1; then
        echo "timeout command not found: $timeout_cmd (on macOS: brew install coreutils, or set TIMEOUT)" >&2
        exit 1
    fi

    if [[ "$require_jdk21" != "0" ]]; then
        local java_major
        java_major="$(java_major_version "$java_bin")"
        if [[ ! "$java_major" =~ ^[0-9]+$ ]] || (( java_major < 21 )); then
            echo "java is too old for the $gate_label: $java_bin reports major version '${java_major:-unknown}', need >= 21." >&2
            if [[ -n "$extra_hint" ]]; then
                echo "$extra_hint" >&2
            fi
            echo "Set JAVA_BIN/JAVA_HOME to a JDK 21+, or DIFF_REQUIRE_JDK21=0 to bypass." >&2
            exit 1
        fi
    fi
}

# Extract flags from "// <directive>: <flags>" lines in a diff test case file
# (e.g. // KOTLINC_FLAGS: -Xfoo). Multiple matching lines are joined with a
# single space; trailing whitespace is trimmed. Prints nothing if absent.
read_case_directive_flags() {
    local case_path="$1" directive="$2"
    { grep -E "^[[:space:]]*//[[:space:]]*${directive}:" "$case_path" 2>/dev/null || true; } \
        | sed "s/.*${directive}:[[:space:]]*//" | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

# Build a validated kotlinc argv array from a case's // KOTLINC_FLAGS:
# directives. Fixtures are untrusted input, so only pure language-feature and
# diagnostic toggles are allowed. Anything that loads JVM code (-Xplugin,
# plugin -P, -J), retargets the classpath/module/JDK, reads external files
# (@argfile, -Xjava-source-roots, ...), or otherwise hijacks the compiler
# command line is rejected before kotlinc ever runs. On success fills the
# named array (possibly empty) and returns 0; on rejection prints the
# offending flag to stderr and returns 1.
validated_kotlinc_flag_argv() {
    local case_path="$1"
    local -n __kotlinc_flags_out="$2"
    __kotlinc_flags_out=()

    local raw_flags
    raw_flags="$(read_case_directive_flags "$case_path" 'KOTLINC_FLAGS')"
    [[ -z "$raw_flags" ]] && return 0

    local -a tokens
    read -r -a tokens <<<"$raw_flags"

    local i token name
    for (( i = 0; i < ${#tokens[@]}; i++ )); do
        token="${tokens[i]}"
        name="${token%%=*}"
        case "$name" in
            # Version options taking a numeric value: -jvm-target 21.
            -jvm-target|-language-version|-api-version)
                local value=""
                if [[ "$token" == *=* ]]; then
                    value="${token#*=}"
                else
                    i=$((i + 1))
                    value="${tokens[i]:-}"
                fi
                if [[ ! "$value" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
                    echo "KOTLINC_FLAGS in $case_path: $name requires a numeric version (got '${value:-<missing>}')" >&2
                    return 1
                fi
                if [[ "$token" == *=* ]]; then
                    __kotlinc_flags_out+=("$token")
                else
                    __kotlinc_flags_out+=("$token" "$value")
                fi
                ;;
            # Language-feature gate: -XXLanguage:+Feature / -XXLanguage:-Feature.
            -XXLanguage:*)
                if [[ ! "$token" =~ ^-XXLanguage:[+-][A-Za-z0-9_]+$ ]]; then
                    echo "KOTLINC_FLAGS in $case_path: malformed -XXLanguage toggle '$token'" >&2
                    return 1
                fi
                __kotlinc_flags_out+=("$token")
                ;;
            # Compiler opt-in: -opt-in=kotlin.RequiresOptIn (repeat per name).
            -opt-in)
                if [[ "$token" != *=* || ! "${token#*=}" =~ ^[A-Za-z_][A-Za-z0-9_.]*$ ]]; then
                    echo "KOTLINC_FLAGS in $case_path: -opt-in requires a single qualified name" >&2
                    return 1
                fi
                __kotlinc_flags_out+=("$token")
                ;;
            # Feature/diagnostic toggles; an optional =value may only carry a
            # scalar mode name, never a path or list.
            -Xexplicit-backing-fields|-Xreturn-value-checker|-Xcontext-parameters|\
-Xcontext-receivers|-Xwhen-guards|-Xmulti-dollar-interpolation|\
-Xnon-local-break-continue|-Xnested-type-aliases|\
-Xdata-flow-based-exhaustiveness|-Xannotation-target-all-params|\
-Xexplicit-api-mode|-Xjspecify-annotations|-Xjvm-default|-Xjdk-release|\
-Xenhance-type-parameter-types-to-def-not-null|-Xlink-via-signatures|\
-Xsuppress-version-warnings|-Xconsistent-data-class-copy-visibility|\
-Xtype-enhancement-improvements-strict-mode)
                if [[ "$token" == *=* && ! "${token#*=}" =~ ^[A-Za-z0-9._+-]+$ ]]; then
                    echo "KOTLINC_FLAGS in $case_path: invalid value for $name" >&2
                    return 1
                fi
                __kotlinc_flags_out+=("$token")
                ;;
            # Warning/progressivity modes.
            -progressive|-nowarn|-Werror|-Wextra)
                if [[ "$token" == *=* ]]; then
                    echo "KOTLINC_FLAGS in $case_path: $name takes no value" >&2
                    return 1
                fi
                __kotlinc_flags_out+=("$token")
                ;;
            *)
                echo "KOTLINC_FLAGS in $case_path: '$token' is not in the allowlist (compiler plugin, classpath, JVM and file-reading options are not permitted)" >&2
                return 1
                ;;
        esac
    done
}

# True (exit 0) when a diff test case should be skipped: it carries a
# // SKIP-DIFF or // KSWIFTK_DIFF_IGNORE directive and $2 (the script's
# --force-run-skipped flag) is not 1.
should_skip_diff_case() {
    local case_path="$1" force_run_skipped="${2:-0}"
    if [[ "$force_run_skipped" -eq 1 ]]; then
        return 1
    fi
    grep -Eq '^[[:space:]]*//[[:space:]]*(KSWIFTK_DIFF_IGNORE|SKIP-DIFF)\b' "$case_path"
}

# Pick a not-yet-existing artifact directory path for a failed diff case:
# "$1/$2", or "$1/${2}_1", "$1/${2}_2", ... on collision. Does not create the
# directory; the caller still owns mkdir/mv. $2 should already be sanitized.
unique_artifact_destination() {
    local artifact_root="$1" case_name="$2"
    local destination="$artifact_root/$case_name"
    local suffix=1
    while [[ -e "$destination" ]]; do
        destination="$artifact_root/${case_name}_$suffix"
        suffix=$((suffix + 1))
    done
    printf '%s' "$destination"
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

# Append the shared --build-system flag (from SWIFT_BUILD_SYSTEM) to the named
# bash array when set. build_swift_tests.sh, swift_test.sh, and
# shard_swift_tests.sh must all select the same build system so swiftbuild's
# per-test-target products and compilation cache are reused across build and
# test invocations.
kswiftk_append_build_system_flag() {
    local -n __flags_array="$1"
    if [[ -n "${SWIFT_BUILD_SYSTEM:-}" ]]; then
        __flags_array+=(--build-system "$SWIFT_BUILD_SYSTEM")
    fi
}
