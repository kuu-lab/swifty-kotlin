#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-stdlib-timings.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cat > "$TEST_DIR/timings.jsonl" <<'EOF'
{"version":1,"id":"a","kind":"artifact-builder","pid":1,"event":"start","timestamp":10}
{"version":1,"id":"b","kind":"cli-stdlib-only","pid":2,"event":"start","timestamp":11}
{"version":1,"id":"a","kind":"artifact-builder","pid":1,"event":"end","timestamp":14,"elapsed_seconds":4,"success":true}
{"version":1,"id":"b","kind":"cli-stdlib-only","pid":2,"event":"end","timestamp":13,"elapsed_seconds":2,"success":false}
{"version":1,"id":"c","kind":"artifact-builder","pid":3,"event":"start","timestamp":15}
not json
EOF
python3 "$SCRIPT_DIR/summarize_stdlib_timings.py" "$TEST_DIR/timings.jsonl" > "$TEST_DIR/result.json"
python3 - "$TEST_DIR/result.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    summary = json.load(stream)
assert summary == {"completed": 2, "failed": 1, "incomplete": 1, "invalid": 1,
                   "peak_concurrent": 2, "duration_seconds_p50": 2, "duration_seconds_p95": 4}, summary
PY
echo 'PASS: stdlib build timing summary'
