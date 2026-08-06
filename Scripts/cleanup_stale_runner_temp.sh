#!/usr/bin/env bash
set -euo pipefail

# Clean only abandoned top-level runner temp entries. The age guard prevents
# removing files from a current job while reclaiming cancelled-job leftovers.
runner_temp="${RUNNER_TEMP:?RUNNER_TEMP is required}"
retention_minutes="${SELF_HOSTED_TEMP_RETENTION_MINUTES:-360}"

if ! [[ "$retention_minutes" =~ ^[1-9][0-9]*$ ]]; then
    echo "SELF_HOSTED_TEMP_RETENTION_MINUTES must be a positive integer: $retention_minutes" >&2
    exit 1
fi

runner_temp="$(cd -- "$runner_temp" && pwd -P)"
if [[ "$(basename "$runner_temp")" != "_temp" || "$(basename "$(dirname "$runner_temp")")" != "_work" ]]; then
    echo "Refusing to clean unexpected runner temp path: $runner_temp" >&2
    exit 1
fi

stale_count=0
while IFS= read -r -d '' stale_path; do
    case "$stale_path" in
        "$runner_temp/_runner_file_commands")
            continue
            ;;
    esac
    echo "Removing stale runner temporary entry: $stale_path"
    rm -rf -- "$stale_path"
    stale_count=$((stale_count + 1))
done < <(find "$runner_temp" -xdev -mindepth 1 -maxdepth 1 -mmin +"$retention_minutes" -print0)

echo "Removed $stale_count stale runner temporary entr$( [[ "$stale_count" == 1 ]] && printf 'y' || printf 'ies' )."
