---
name: testing-completion-gates
description: How to run the swifty-kotlin completion gates (swift_test.sh, Golden, diff_kotlinc.sh) on a Linux box, avoid tmpfs exhaustion, set up kotlinc/JDK for the diff gate, and distinguish pre-existing environment failures from PR regressions.
---

# Running swifty-kotlin completion gates (Linux)

Gates (all must be green, cwd = repo root; run `source ~/.bashrc` first for Swift/LLVM env):
1. `bash Scripts/swift_test.sh`            # full suite, long
2. `bash Scripts/swift_test.sh --filter Golden`
3. `bash Scripts/diff_kotlinc.sh Scripts/diff_cases`
Aux: `bash Scripts/validate_runtime_abi_links.sh`, `git diff --check`

## Critical: avoid /tmp (tmpfs) exhaustion
`/tmp` is tmpfs (~16GB). The full suite's CodegenBackendIntegrationTests leave ~1000 scratch
dirs (~13MB each) that fill tmpfs mid-run and cause `No space left on device` near the end
(~test 3047/3110). Fix: run with `export TMPDIR=/home/ubuntu/tmp` (disk-backed /dev/root, ~100GB).
Disk-backed TMPDIR is slower (full suite ~1.5–2h) but reliable. Clean stragglers between runs:
`rm -rf /tmp/????????-????-????-????-????????????`.

## Diff gate needs JDK 21 + Kotlin 2.3.10 (not preinstalled)
Default box has JDK 17 and no kotlinc; `diff_kotlinc.sh` needs JDK 21 + Kotlin 2.3.10.
Install to home (no sudo for /opt):
- JDK21: download openjdk-21 tarball → `~/tools/jdk21`
- Kotlin: `kotlin-compiler-2.3.10.zip` from JetBrains releases → unzip to `~/tools/` (`~/tools/kotlinc`)
Then run diff gate with: `export JAVA_HOME=/home/ubuntu/tools/jdk21; export PATH=$JAVA_HOME/bin:/home/ubuntu/tools/kotlinc/bin:$PATH`.
The harness auto-downloads kotlinx-coroutines and buffers PASS/FAIL to the log; when output is
redirected to a file, lines flush only at the end. Track progress via `pgrep -af diff_cases`
(cases run alphabetically) and failures via `.artifacts/diff_kotlinc/` (empty = no failures).

## Distinguishing pre-existing env failures from PR regressions
This box runs Swift 6.2.4 + LLVM 14, but CI uses Swift 6.3 + LLVM 18 (see AGENTS.md). Some
`CodegenBackendIntegrationTests` (collection/sequence/string codegen) fail here with runtime
crashes (Signal 11 in `kk_array_*` lambdas, `KSWIFTK-RUNTIME-0001 vtable dispatch failed`) or
`XCTAssertTrue` callee-list mismatches — these are pre-existing/environmental, NOT PR bugs.
To prove: `git worktree add /tmp/base <base-commit>` and re-run the same failing tests there;
identical failures = pre-existing. Do NOT `git checkout` in the shared repo (the lead may share
the working dir) — use a worktree.

## Test-name filters / frameworks
Sema/annotation tests use Swift Testing `@Suite` (output `◇/✔/✘`, "Test run with N tests"),
not XCTest ("Executed N tests"). `--filter <SuiteName>` works for both; a Swift-Testing suite
matching still prints "Executed 0 tests" on the XCTest side — check the `✔ Suite ... passed` line.
Key KSP-667 suites: `NativePlatformAnnotationTests`, `NativeRefRuntimeSemaTests`.

## Devin Secrets Needed
None. All tooling is downloaded from public sources; no credentials required.
