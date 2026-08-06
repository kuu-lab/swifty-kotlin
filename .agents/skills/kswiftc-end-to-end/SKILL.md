---
name: kswiftc End-to-End Sample & IR Parity Testing
description: How to build kswiftc, run diff_kotlinc sample programs, diff LLVM IR against a master baseline, and execute targeted CompilerBackendTests suites.
---

# kswiftc End-to-End Sample & IR Parity Testing

## Devin Secrets Needed
None. This workflow relies only on the repo blueprint (Swift + LLVM + `kotlinc`) being applied.

## Common gotchas

- If `.build/debug/kswiftc` is not rebuilt after a source change, run `swift package clean` before `swift build`. SwiftPM incremental builds can skip re-linking when git-checkout preserves older source mtimes than the binary.
- The current toolchain VM ships OpenJDK 17, but `Scripts/diff_kotlinc.sh` defaults to requiring JDK 21. For integer/string-only diff cases set `DIFF_REQUIRE_JDK21=0` so the harness runs under JDK 17. Float/Double `toString()` formatting can still differ between JDK 17 and 21, so avoid float cases in this mode.
- `diff_kotlinc.sh` auto-downloads `kotlinx-coroutines-core-jvm` for cases that `import kotlinx.coroutines.*`.
- If `/tmp` fills up, set `TMPDIR=/home/ubuntu/tmp` and `mkdir -p /home/ubuntu/tmp` first.
- `swift test --filter` accepts a regular expression. The specifier format is `CompilerBackendTests.SuiteName/testName`, so filtering by suite name (e.g. `BackendDriverOutputTests`) works.

## Build

```bash
swift package clean   # only if the binary looks stale
swift build
.build/debug/kswiftc --help
```

## Run a single diff sample

```bash
TMPDIR=/home/ubuntu/tmp DIFF_REQUIRE_JDK21=0 \
  bash Scripts/diff_kotlinc.sh --no-parallel --run-timeout 30 \
  Scripts/diff_cases/hello.kt
```

Expected: `PASS Scripts/diff_cases/hello.kt`.

## LLVM IR parity against master

Use a git worktree to keep both branches built side-by-side:

```bash
cd /home/ubuntu/repos/swifty-kotlin
git worktree add /home/ubuntu/repos/swifty-kotlin-master master
cd /home/ubuntu/repos/swifty-kotlin-master && swift build
cd /home/ubuntu/repos/swifty-kotlin
.build/debug/kswiftc --emit llvm -o /home/ubuntu/tmp/pr.ll Scripts/diff_cases/hello.kt
/home/ubuntu/repos/swifty-kotlin-master/.build/debug/kswiftc \
  --emit llvm -o /home/ubuntu/tmp/master.ll Scripts/diff_cases/hello.kt
diff -u /home/ubuntu/tmp/master.ll /home/ubuntu/tmp/pr.ll
```

Expected: empty diff.

## Targeted CompilerBackendTests suites

```bash
TMPDIR=/home/ubuntu/tmp SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh \
  --filter 'BackendDriverOutputTests|LoweringCodegenRegressionTests|VirtualDispatchCodegenTests|NameManglerTests|LinkPhaseIntegrationTests'
```

Or, if the regex is rejected, run each suite separately.

## Useful samples for function-resolution / IR stress

- `Scripts/diff_cases/overload.kt` — top-level overloads by type.
- `Scripts/diff_cases/class_and_function_same_name.kt` — class and top-level functions share a name.
- `Scripts/diff_cases/extension_receiver.kt` — extension function on `Int`.
- `Scripts/diff_cases/list_filter_is_instance.kt` — `filterIsInstance` on `List<Any>`.
- `Scripts/diff_cases/sequence_lazy.kt` — `asSequence` / `toList` / HOF chains.
- `Scripts/diff_cases/iterator_builder.kt` — `iterator { yield(...) }` builder.
- `Scripts/diff_cases/coroutine_launch_join.kt` — small coroutine example.
- `Scripts/diff_cases/collection_builders.kt` — `buildString` / `buildList` / `buildSet` / `buildMap`.
- `Scripts/diff_cases/function_types.kt` — function-type variables and higher-order functions.
