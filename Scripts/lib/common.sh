# Shared shell helpers for Scripts/*.sh

[[ -n "${_KSWIFTK_SCRIPTS_COMMON_SH:-}" ]] && return 0
_KSWIFTK_SCRIPTS_COMMON_SH=1

# Canonical golden-update command, shown in failure hints. Keep in sync with
# the "Golden update workflow" section of Scripts/README.md.
GOLDEN_UPDATE_CMD="UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden"

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
