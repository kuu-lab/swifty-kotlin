#!/usr/bin/env bash
# Coordinate focused SwiftPM builds with swift_test.sh across local worktrees.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

build_slots=""
kswiftk_resolve_build_slots build_slots
has_jobs_flag=false
for arg in "$@"; do
    case "$arg" in
        -j|-j[0-9]*|--jobs|--jobs=*) has_jobs_flag=true ;;
    esac
done

declare -a command=(swift build)

# Match swift_test.sh so alternating focused builds and tests does not change
# SwiftPM's build system, plugin search path, or compilation cache settings.
kswiftk_append_build_system_flag command
kswiftk_append_testing_plugin_path command
kswiftk_setup_compile_cache_env
kswiftk_append_compile_cache_flags command

if [[ "$has_jobs_flag" == false ]]; then
    build_jobs="${SWIFT_BUILD_JOBS:-}"
    if [[ -z "$build_jobs" ]]; then
        build_jobs="$(detect_workers)"
        if [[ "$build_slots" -gt 0 && "$build_jobs" =~ ^[1-9][0-9]*$ ]]; then
            build_jobs=$(( (build_jobs + build_slots - 1) / build_slots ))
        fi
    fi
    if [[ -n "$build_jobs" ]]; then
        command+=(-j "$build_jobs")
    fi
fi
command+=("$@")
kswiftk_wrap_build_slots command "$build_slots" "$SCRIPT_DIR"
exec "${command[@]}"
