#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

OUTPUT_DIR=""
KEEP_TMP=0
VERBOSE=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Dead-code audit for @_cdecl kk_* runtime symbols.

Detects kk_* functions declared in Sources/Runtime that cannot be reached
by compiled Kotlin programs. Uses identifier-frequency analysis across
Sources/, Tests/, and *.kt files.

Exclusion pipeline (reproduces docs/dead-code-audit.md):
  1. Static emit      — CompilerCore kk_* identifier references
  2. Dynamic emit     — string-interpolation prefixes ("kk_xxx_\(...)")
  3. Table-driven     — StdlibSurfaceSpec collectionHOFRuntimeLinkName entries
                        (list / set / map / sequence HOF; array is separate)
  4. Test references  — Tests/ direct calls (word-boundary match)
  5. Runtime-internal — non-@_cdecl kk_* appearances inside Sources/Runtime

Output categories:
  A: Completely unreachable — no path from compiler, tests, or runtime internals
  B: Test-only             — reachable only from Tests/

Options:
  --output-dir <dir>   Write intermediate .txt files here (default: auto temp dir)
  --keep-tmp           Keep temp dir after exit (implied by --output-dir)
  --verbose, -v        Print step-by-step counts to stderr
  -h, --help           Show this help

Examples:
  bash Scripts/dead_code_audit.sh
  bash Scripts/dead_code_audit.sh --verbose
  bash Scripts/dead_code_audit.sh --output-dir /tmp/audit_out
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      shift
      [[ $# -eq 0 ]] && { echo "--output-dir requires an argument" >&2; exit 1; }
      OUTPUT_DIR="$1"
      ;;
    --output-dir=*)
      OUTPUT_DIR="${1#*=}"
      ;;
    --keep-tmp)
      KEEP_TMP=1
      ;;
    --verbose|-v)
      VERBOSE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -n "$OUTPUT_DIR" ]]; then
  WORK="$OUTPUT_DIR"
  KEEP_TMP=1
else
  WORK="$(mktemp -d -t dead_code_audit_XXXXXX)"
fi
mkdir -p "$WORK"

if [[ $KEEP_TMP -eq 0 ]]; then
  trap 'rm -rf "$WORK"' EXIT
fi

log() {
  [[ $VERBOSE -eq 1 ]] && printf '%s\n' "$*" >&2 || true
}

# ── Step 1: Runtime の @_cdecl kk_* 宣言一覧 ──────────────────────────────
grep -rhoE '@_cdecl\("kk_[a-zA-Z0-9_]+"\)' Sources/Runtime --include="*.swift" \
    | sed 's/@_cdecl("//;s/")//' \
    | LC_ALL=C sort -u > "$WORK/runtime_cdecl.txt"
log "[1] Runtime @_cdecl declarations: $(wc -l < "$WORK/runtime_cdecl.txt" | tr -d ' ')"

# ── Step 2: CompilerCore の静的 kk_* 参照 ────────────────────────────────
grep -rhoE 'kk_[a-zA-Z0-9_]+' Sources/CompilerCore --include="*.swift" \
    | LC_ALL=C sort -u > "$WORK/kk_compilercore.txt"
log "[2] CompilerCore static refs: $(wc -l < "$WORK/kk_compilercore.txt" | tr -d ' ')"

# ── Step 3: 動的補間プレフィックス（前方一致除外用） ──────────────────────
grep -rhoE '"kk_[a-zA-Z0-9_]*\\\(' Sources/CompilerCore --include="*.swift" \
    | sed 's/^"//;s/\\($//' \
    | LC_ALL=C sort -u > "$WORK/kk_dyn_prefixes.txt"
log "[3] Dynamic interpolation prefixes: $(wc -l < "$WORK/kk_dyn_prefixes.txt" | tr -d ' ')"

# ── Step 4: StdlibSurfaceSpec 表駆動 HOF リンク名 ─────────────────────────
# list / set / map / sequence の HOF（array は RuntimeOnlyBridge で別管理のため対象外）
grep -rhoE '"kk_[a-zA-Z0-9_]+"' Sources/RuntimeABI \
    --include="StdlibSurfaceSpec+*.swift" \
    | sed 's/"//g' \
    | LC_ALL=C sort -u > "$WORK/kk_stdlib_surface.txt"
log "[4] StdlibSurfaceSpec link names: $(wc -l < "$WORK/kk_stdlib_surface.txt" | tr -d ' ')"

# ── Step 5: Tests からの参照（語境界一致） ────────────────────────────────
# superstring 誤検知に注意: kk_http_client_post と kk_http_client_post_async は別物
(grep -rhoE '\bkk_[a-zA-Z0-9_]+\b' Tests --include="*.swift" || true) \
    | LC_ALL=C sort -u > "$WORK/kk_tests.txt"
log "[5] Test references: $(wc -l < "$WORK/kk_tests.txt" | tr -d ' ')"

# ── Step 6: Runtime 内部参照（宣言行を除くコード行に現れる kk_*） ──────────
# @_cdecl 行と func 定義行を除外することで、他の Runtime 関数からの実際の呼び出しを取得する
(grep -rh 'kk_[a-zA-Z0-9_]' Sources/Runtime --include="*.swift" || true) \
    | grep -v '@_cdecl' \
    | grep -v '\bfunc kk_' \
    | grep -oE 'kk_[a-zA-Z0-9_]+' \
    | LC_ALL=C sort -u > "$WORK/kk_runtime_internal.txt" || true
log "[6] Runtime-internal refs: $(wc -l < "$WORK/kk_runtime_internal.txt" | tr -d ' ')"

# ── Step 7: 動的プレフィックスに前方一致する cdecl 名を抽出 ──────────────
{
  while IFS= read -r prefix; do
    grep "^${prefix}" "$WORK/runtime_cdecl.txt" || true
  done < "$WORK/kk_dyn_prefixes.txt"
} | LC_ALL=C sort -u > "$WORK/kk_dyn_matched.txt"
log "[7] Dynamic-prefix matched cdecl names: $(wc -l < "$WORK/kk_dyn_matched.txt" | tr -d ' ')"

# ── Step 8: コンパイラ到達可能集合（静的 + 動的 + 表駆動） ───────────────
LC_ALL=C sort -u "$WORK/kk_compilercore.txt" \
                 "$WORK/kk_dyn_matched.txt" \
                 "$WORK/kk_stdlib_surface.txt" > "$WORK/kk_reachable.txt"
log "[8] Compiler-reachable total: $(wc -l < "$WORK/kk_reachable.txt" | tr -d ' ')"

# ── Step 9: 候補 = cdecl − コンパイラ到達可能 ────────────────────────────
comm -23 "$WORK/runtime_cdecl.txt" "$WORK/kk_reachable.txt" \
    > "$WORK/kk_candidates.txt"
log "[9] Candidates (compiler-unreachable): $(wc -l < "$WORK/kk_candidates.txt" | tr -d ' ')"

# ── Step 10: A = 候補 − (tests ∪ runtime_internal) ───────────────────────
LC_ALL=C sort -u "$WORK/kk_tests.txt" "$WORK/kk_runtime_internal.txt" \
    > "$WORK/kk_tests_or_internal.txt"
comm -23 "$WORK/kk_candidates.txt" "$WORK/kk_tests_or_internal.txt" \
    > "$WORK/dead_A.txt"

# ── Step 11: B = (候補 ∩ tests) − runtime_internal ───────────────────────
comm -12 "$WORK/kk_candidates.txt" "$WORK/kk_tests.txt" \
    > "$WORK/kk_candidates_in_tests.txt"
comm -23 "$WORK/kk_candidates_in_tests.txt" "$WORK/kk_runtime_internal.txt" \
    > "$WORK/dead_B.txt"

# ── 出力 ──────────────────────────────────────────────────────────────────
COUNT_CDECL="$(wc -l < "$WORK/runtime_cdecl.txt" | tr -d ' ')"
COUNT_CAND="$(wc -l < "$WORK/kk_candidates.txt" | tr -d ' ')"
COUNT_A="$(wc -l < "$WORK/dead_A.txt" | tr -d ' ')"
COUNT_B="$(wc -l < "$WORK/dead_B.txt" | tr -d ' ')"

echo "=== Dead Code Audit ==="
echo "Runtime @_cdecl total  : $COUNT_CDECL"
echo "Compiler-unreachable   : $COUNT_CAND  (A + B + runtime-internal-only)"
echo ""
echo "--- A: Completely unreachable ($COUNT_A) ---"
cat "$WORK/dead_A.txt"
echo ""
echo "--- B: Test-only references ($COUNT_B) ---"
cat "$WORK/dead_B.txt"

if [[ -n "$OUTPUT_DIR" ]]; then
  echo ""
  echo "Intermediate files written to: $WORK"
fi
