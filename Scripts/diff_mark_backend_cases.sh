#!/usr/bin/env bash
# Opt diff cases into a non-native backend lane based on a sweep report.
#
# Reads a diff_kotlinc.sh --report TSV produced with DIFF_BACKEND_SWEEP=1 and
# prepends `// DIFF_<BACKEND>` to every case whose status is PASS and that is
# not already marked, so the case joins the gated backend lane in nightly.
#
# Usage:
#   diff_mark_backend_cases.sh <report.tsv> <jvm|wasm> [--dry-run]
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <report.tsv> <jvm|wasm> [--dry-run]" >&2
  exit 2
fi

report="$1"
backend="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
dry_run=0
if [[ "${3:-}" == "--dry-run" ]]; then
  dry_run=1
elif [[ -n "${3:-}" ]]; then
  echo "unknown argument: $3" >&2
  exit 2
fi

case "$backend" in
  jvm|wasm) ;;
  *) echo "backend must be jvm or wasm (got: $2)" >&2; exit 2 ;;
esac

if [[ ! -f "$report" ]]; then
  echo "report not found: $report" >&2
  exit 1
fi

marker_name="DIFF_$(printf '%s' "$backend" | tr '[:lower:]' '[:upper:]')"
marker="// $marker_name"
marked=0
already=0

while IFS=$'\t' read -r path status _rest; do
  [[ "$status" == "PASS" && -f "$path" ]] || continue
  if grep -Eq "^[[:space:]]*//[[:space:]]*${marker_name}\\b" "$path"; then
    already=$((already + 1))
    continue
  fi
  if (( dry_run )); then
    echo "would mark: $path"
  else
    tmp="$(mktemp "${path}.XXXXXX")"
    printf '%s\n' "$marker" >"$tmp"
    cat "$path" >>"$tmp"
    mv "$tmp" "$path"
  fi
  marked=$((marked + 1))
done <"$report"

echo "backend=$backend marker=$marker marked=$marked already_marked=$already dry_run=$dry_run"
