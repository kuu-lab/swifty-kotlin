#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCAN_DIRS=("$ROOT_DIR/.github/workflows" "$ROOT_DIR/.github/actions")

usage() {
  cat <<USAGE
Usage: $(basename "$0")

Verify that no GitHub Actions workflow or composite action installs or
executes npm packages outside of an \`npm ci\` against a committed
package-lock.json.

Forbidden in .github/workflows and .github/actions:
\`npm install\`, \`npm i\`, \`npm update\`, \`npm uninstall\`,
\`npm exec\`, \`npx\`, \`pnpm\`, \`yarn\`, \`bunx\`, \`bun x\`.

Allowed: \`npm ci\` (deterministic, integrity-checked install from a
committed lockfile, run with --ignore-scripts in this repository).

Rationale: ad-hoc installs resolve transitive dependencies and lifecycle
scripts from the registry at run time, so a compromised transitive
release could execute code on CI runners. See .github/ci-tools/.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

for dir in "${SCAN_DIRS[@]}"; do
  if [[ ! -d "$dir" ]]; then
    echo "Scan directory not found: $dir" >&2
    exit 1
  fi
done

# npm ci is the only permitted npm invocation; everything else that can
# pull package code from a registry is rejected.
pattern='\bnpm[[:space:]]+(install|i|update|uninstall|exec)\b|\bnpx\b|\bpnpm\b|\byarn\b|\bbunx\b|\bbun[[:space:]]+x\b'

hits="$(grep -rnE "$pattern" "${SCAN_DIRS[@]}" --include='*.yml' --include='*.yaml' || true)"

if [[ -n "$hits" ]]; then
  echo "Forbidden package install/execution commands found in GitHub workflows/actions:" >&2
  echo "$hits" >&2
  echo >&2
  echo "Install npm-based CI tools via a committed lockfile instead:" >&2
  echo "  cp .github/ci-tools/{package.json,package-lock.json,.npmrc} <tmpdir>/ && npm ci --prefix <tmpdir> --ignore-scripts" >&2
  exit 1
fi

echo "OK: workflows and actions use no ad-hoc npm installs (npm ci only)."
