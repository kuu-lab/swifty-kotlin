#!/usr/bin/env bash
set -euo pipefail
cd "/home/runner/work/swifty-kotlin/swifty-kotlin"
bash Scripts/diff_kotlinc.sh --no-parallel --keep-temp --force-run-skipped "Scripts/diff_cases/multi_dollar_string.kt"
