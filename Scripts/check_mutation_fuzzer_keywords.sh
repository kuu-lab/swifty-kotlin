#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

TOKEN_MODEL="$ROOT_DIR/Sources/CompilerCore/Lexer/TokenModel.swift"
MUTATOR="$ROOT_DIR/Scripts/mutate_diff_cases.py"

usage() {
  cat <<USAGE
Usage: $(basename "$0")

Verify that Scripts/mutate_diff_cases.py's IDENTIFIER_KEYWORDS set exactly
matches the hard-keyword \`Keyword\` enum in
Sources/CompilerCore/Lexer/TokenModel.swift, so the mutation fuzzer's
keyword/identifier token classification never silently drifts from the
lexer it is fuzzing.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f "$TOKEN_MODEL" ]]; then
  echo "Token model not found: $TOKEN_MODEL" >&2
  exit 1
fi

if [[ ! -f "$MUTATOR" ]]; then
  echo "Mutation fuzzer script not found: $MUTATOR" >&2
  exit 1
fi

"$PYTHON_BIN" - "$TOKEN_MODEL" "$MUTATOR" <<'PY'
import ast
import re
import sys

token_model_path, mutator_path = sys.argv[1], sys.argv[2]

swift_source = open(token_model_path, encoding="utf-8").read()
match = re.search(r"public enum Keyword: String, Sendable \{(.*?)\n\}", swift_source, re.S)
if match is None:
    raise SystemExit(f"Could not find `Keyword` enum in {token_model_path}")
swift_keywords = set(re.findall(r"case\s+`?([A-Za-z_][A-Za-z0-9_]*)`?", match.group(1)))

tree = ast.parse(open(mutator_path, encoding="utf-8").read(), filename=mutator_path)
python_keywords = None
for node in ast.walk(tree):
    if isinstance(node, ast.Assign) and any(
        getattr(target, "id", None) == "IDENTIFIER_KEYWORDS" for target in node.targets
    ):
        python_keywords = ast.literal_eval(node.value)
        break
if python_keywords is None:
    raise SystemExit(f"Could not find IDENTIFIER_KEYWORDS assignment in {mutator_path}")

missing = swift_keywords - python_keywords
extra = python_keywords - swift_keywords
if missing or extra:
    if missing:
        print(f"Keywords in TokenModel.swift missing from IDENTIFIER_KEYWORDS: {sorted(missing)}", file=sys.stderr)
    if extra:
        print(f"Entries in IDENTIFIER_KEYWORDS that are not hard keywords in TokenModel.swift: {sorted(extra)}", file=sys.stderr)
    raise SystemExit(1)

print(f"IDENTIFIER_KEYWORDS matches the {len(swift_keywords)} hard keywords in TokenModel.swift.")
PY
