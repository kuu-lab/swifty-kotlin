// SKIP-DIFF (DEBT-DIFF-009): kotlinc -script reports every runtime failure as
// exit=3 (SCRIPT_EXECUTION_ERROR) regardless of cause, while kswiftc's
// compiled binary reports an unhandled top-level exception as exit=1
// (KSWIFTK-LINK-0003 panic) — a pre-existing exit-code-convention gap between
// the two runners, independent of the ref-side compile/run classification in
// Scripts/diff_kotlinc.sh's run_case(). This case is the minimal repro that
// classification bug was diagnosed against: with --force-run-skipped it now
// correctly reports "script exit mismatch: ref=3 candidate=1" instead of the
// old, misleading "compile exit mismatch: ref=3 candidate=0" (the ref side
// never actually failed to compile).
val x = 10 / 0
println("unreachable")
