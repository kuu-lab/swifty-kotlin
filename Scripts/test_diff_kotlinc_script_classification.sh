#!/usr/bin/env bash
# Regression test for Scripts/diff_kotlinc.sh's run_case() script-mode exit
# classification (see docs/diff-skip-inventory.md DEBT-DIFF-009).
#
# kotlinc -script bundles compile+run into one JVM process, so there is no
# independently observable compile-phase exit on the reference side. This
# used to be recovered with a "nonzero exit + empty stdout => compile
# failure" heuristic, which misclassified a script that throws before
# printing anything as a compile failure — even though it compiled fine and
# only failed at runtime. Since the candidate (kswiftc) genuinely compiles
# and runs in two separate steps, that misclassification produced a
# misleading "compile exit mismatch" report (with empty stderr on both
# sides) instead of the real run/script exit mismatch.
#
# This test drives the real diff_kotlinc.sh end to end against fake
# kotlinc/kswiftc binaries so it pins the classification logic itself,
# independent of kswiftc's actual runtime fidelity (which drifts over time).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kswiftk-diff-classification-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

FAKE_BIN_DIR="$TEMP_DIR/fake_bin"
mkdir -p "$FAKE_BIN_DIR"

# Fake kotlinc: only understands `-version` (warm-up) and `-script <file>`.
# For a script whose name contains "mismatch", simulates a script that
# compiles fine but throws an uncaught exception before printing anything:
# empty stdout, exit 3 (mirroring kotlinc's real SCRIPT_EXECUTION_ERROR code,
# confirmed empirically against kotlinc 2.4.10). For "okcase", prints
# matching stdout and exits 0. For "candcompilefail", also succeeds (ref
# compiles+runs fine) — the candidate is the one that fails to compile below.
cat >"$FAKE_BIN_DIR/fake_kotlinc" <<'EOF'
#!/usr/bin/env bash
script_arg=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-script" ]]; then
    script_arg="$arg"
  fi
  prev="$arg"
done
if [[ -z "$script_arg" ]]; then
  echo "fake kotlinc" >&2
  exit 0
fi
case "$(basename "$script_arg")" in
  *mismatch*)
    echo "java.lang.ArithmeticException: / by zero" >&2
    exit 3
    ;;
  *candcompilefail*)
    echo "ok output from script"
    exit 0
    ;;
  *okcase*)
    echo "ok output from script"
    exit 0
    ;;
  *)
    echo "fake_kotlinc: unrecognized script fixture: $script_arg" >&2
    exit 90
    ;;
esac
EOF
chmod +x "$FAKE_BIN_DIR/fake_kotlinc"

# Fake kswiftc: only understands the candidate-compile invocation
# ("... <file> -o <bin>"). For "mismatch"/"okcase" it always "compiles"
# successfully and produces a stub binary whose behavior depends on the
# fixture — a deliberately different run exit (7) than the fake kotlinc's 3
# for the mismatch case, so a real run/script exit mismatch is
# distinguishable from the old, misreported "compile exit mismatch". For
# "candcompilefail" it fails to compile (nonzero exit, no binary produced),
# covering the is_script branch where the candidate never gets to run.
cat >"$FAKE_BIN_DIR/fake_kswiftc" <<'EOF'
#!/usr/bin/env bash
out=""
src=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "-o" ]]; then
    out="$arg"
  fi
  if [[ "$arg" == *.kt ]]; then
    src="$arg"
  fi
  prev="$arg"
done
if [[ -z "$out" ]]; then
  exit 0
fi
case "$(basename "$src")" in
  *mismatch*)
    { echo '#!/usr/bin/env bash'; echo 'exit 7'; } >"$out"
    ;;
  *candcompilefail*)
    echo "fake compile error: something went wrong" >&2
    exit 42
    ;;
  *okcase*)
    { echo '#!/usr/bin/env bash'; echo 'echo "ok output from script"'; echo 'exit 0'; } >"$out"
    ;;
  *)
    echo "fake_kswiftc: unrecognized source fixture: $src" >&2
    exit 91
    ;;
esac
[[ -f "$out" ]] && chmod +x "$out"
exit 0
EOF
chmod +x "$FAKE_BIN_DIR/fake_kswiftc"

FAKE_STDLIB_DIR="$TEMP_DIR/fake_stdlib"
mkdir -p "$FAKE_STDLIB_DIR"
echo '{}' >"$FAKE_STDLIB_DIR/manifest.json"

CASES_DIR="$TEMP_DIR/cases"
mkdir -p "$CASES_DIR"
printf 'val x = 10 / 0\nprintln("unreachable")\n' >"$CASES_DIR/script_mismatch.kt"
printf 'println("ok output from script")\n' >"$CASES_DIR/script_okcase.kt"
printf 'println("ok output from script")\n' >"$CASES_DIR/script_candcompilefail.kt"

ARTIFACT_ROOT="$TEMP_DIR/artifacts"
OUTPUT_LOG="$TEMP_DIR/output.log"

set +e
KOTLINC="$FAKE_BIN_DIR/fake_kotlinc" \
KSWIFTC="$FAKE_BIN_DIR/fake_kswiftc" \
DIFF_STDLIB_LIBRARY="$FAKE_STDLIB_DIR" \
DIFF_REQUIRE_JDK21=0 \
DIFF_ARTIFACT_ROOT="$ARTIFACT_ROOT" \
bash "$ROOT_DIR/Scripts/diff_kotlinc.sh" --no-parallel "$CASES_DIR" >"$OUTPUT_LOG" 2>&1
set -e

fail() {
  echo "FAIL: $1" >&2
  echo "--- diff_kotlinc.sh output ---" >&2
  cat "$OUTPUT_LOG" >&2
  exit 1
}

if grep -q "compile exit mismatch" "$OUTPUT_LOG"; then
  fail "script_mismatch.kt must not be reported as a compile exit mismatch — it compiled fine and only failed at runtime (the bug this test guards against)"
fi

if ! grep -q "script exit mismatch: ref=3 candidate=7" "$OUTPUT_LOG"; then
  fail "script_mismatch.kt should report a script exit mismatch (ref=3 candidate=7)"
fi

if ! grep -q "ref script stderr:" "$OUTPUT_LOG"; then
  fail "script_mismatch.kt's FAIL report should include the ref script's actual stderr"
fi

if ! grep -qF "PASS $CASES_DIR/script_okcase.kt" "$OUTPUT_LOG"; then
  fail "script_okcase.kt (happy path, both sides exit 0 with matching stdout) should PASS"
fi

# script_candcompilefail.kt: the reference script succeeds, but the
# candidate's (genuinely separate) compile step fails. This must be reported
# against the candidate's compile exit, not misread as a run-phase issue,
# and the candidate's real compile stderr must be visible in the report —
# with no "candidate run stderr:" section, since the candidate never ran.
if ! grep -q "script exit mismatch: ref=0 candidate=42" "$OUTPUT_LOG"; then
  fail "script_candcompilefail.kt should report a script exit mismatch (ref=0 candidate=42)"
fi
if ! grep -q "fake compile error: something went wrong" "$OUTPUT_LOG"; then
  fail "script_candcompilefail.kt's FAIL report should include the candidate's actual compile stderr"
fi
# Only script_mismatch.kt's candidate actually compiled and ran (exit 7), so
# exactly one "candidate run stderr:" section should appear across both FAIL
# cases — script_candcompilefail.kt's candidate never compiled, so it must
# not get one.
candidate_run_stderr_sections="$(grep -c "candidate run stderr:" "$OUTPUT_LOG" || true)"
if [[ "$candidate_run_stderr_sections" -ne 1 ]]; then
  fail "expected exactly 1 'candidate run stderr:' section (from script_mismatch.kt only), found $candidate_run_stderr_sections"
fi

echo "OK: diff_kotlinc.sh script-mode exit classification behaves correctly"
