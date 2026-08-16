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

## KSP stdlib migration verification (StateFlow / SharedFlow)

For PRs that migrate `StateFlow`, `MutableStateFlow`, `Flow.stateIn`, `SharedFlow`, `MutableSharedFlow`, or `Flow.shareIn` from runtime C bridges to bundled Kotlin source:

- Required environment on the Linux VM:

  ```bash
  export C_INCLUDE_PATH=/usr/lib/llvm-14/include
  export LIBRARY_PATH=/usr/lib/llvm-14/lib
  export KSWIFTK_LLVM_DYLIB=/usr/lib/llvm-14/lib/libLLVM.so
  ```

- Run `swift package clean && swift build` first. SwiftPM incremental builds can skip re-linking when checkout timestamps are stale.
- Run `bash Scripts/validate_runtime_abi_links.sh` to confirm the removed `kk_*` bridges no longer cause ABI validation failures.
- Run Swift tests serially: `SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --filter SmokeTests`
- Run the targeted artifact regression test: `SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --filter StdlibArtifactRegressionTests/testStateFlowThroughSharedStdlibArtifact`
- Build and execute the diff samples directly:

  ```bash
  .build/debug/kswiftc Scripts/diff_cases/state_flow_kotlin.kt -o /tmp/state_flow && /tmp/state_flow
  .build/debug/kswiftc Scripts/diff_cases/shared_flow_kotlin.kt -o /tmp/shared_flow && /tmp/shared_flow
  ```

  Expected output for `state_flow_kotlin.kt`:

  ```
  10
  20
  30
  30
  [30]
  3
  [6]
  ```

  Expected output for `shared_flow_kotlin.kt`:

  ```
  []
  true
  [2, 3]
  [2, 3]
  true
  []
  ```

- The `stateIn` / `shareIn` bundled sources in this repo intentionally use simplified signatures (`stateIn(initialValue: T)` and `shareIn(replay: Int)`) that do not match the JVM `kotlinx.coroutines` API (`CoroutineScope` / `SharingStarted` parameters). Because of this, `Scripts/diff_cases/state_flow_kotlin.kt` and `Scripts/diff_cases/shared_flow_kotlin.kt` will **not** compile against reference `kotlinc` and are not suitable for `Scripts/diff_kotlinc.sh`. Use `diff_kotlinc.sh` only on JVM-compatible coroutine cases.
- If `diff_kotlinc.sh` must be run for a coroutine case and Maven access is unavailable or rate-limited, provide a local `kotlinx-coroutines-core-jvm` jar instead of letting the script download one:

  ```bash
  KOTLINC_CLASSPATH=/path/to/kotlinx-coroutines-core-jvm.jar \
    DIFF_REQUIRE_JDK21=0 bash Scripts/diff_kotlinc.sh Scripts/diff_cases/some_coroutine_case.kt
  ```

## KSP stdlib migration verification (Comparator)

For PRs that migrate `kotlin.Comparator` (or similar stdlib declarations) from a synthetic Sema stub to a bundled Kotlin source while keeping a minimal synthetic placeholder:

- Required environment on the Linux VM:

  ```bash
  export PATH=/opt/swift-6.3.1/usr/bin:/home/ubuntu/.runtime-build/kotlin-tools/kotlinc/bin:/home/ubuntu/.runtime-build/jdk21/bin:$PATH
  export JAVA_HOME=/home/ubuntu/.runtime-build/jdk21
  export JAVACMD=/home/ubuntu/.runtime-build/jdk21/bin/java
  export KOTLINC=/home/ubuntu/.runtime-build/kotlin-tools/kotlinc/bin/kotlinc
  export C_INCLUDE_PATH=/usr/lib/llvm-14/include
  export LIBRARY_PATH=/usr/lib/llvm-14/lib
  export LD_LIBRARY_PATH=/usr/lib/llvm-14/lib
  export KSWIFTK_LLVM_DYLIB=/usr/lib/llvm-14/lib/libLLVM.so
  ```

- Run `swift package clean && swift build` first. SwiftPM incremental builds can skip re-linking when checkout timestamps are stale.
- Run the Sema golden suite to exercise the bundled source symbol flags and the synthetic-placeholder reuse path:

  ```bash
  SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --filter GoldenSemaGoldenTests -Xswiftc -swift-version -Xswiftc 6
  ```

  Also run `StringSyntheticMemberLinkTests/testStringSyntheticMemberLinkCleanCallExpressions` because `String.Companion.CASE_INSENSITIVE_ORDER` resolves `kotlin.Comparator` early.
- Run the targeted diff case and execute the binary directly:

  ```bash
  bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_n_Comparator.kt
  .build/debug/kswiftc Scripts/diff_cases/stdlib_kotlin_n_Comparator.kt -o /tmp/comparator_test && /tmp/comparator_test
  ```

  Expected output (based on the current source `{ a, b -> a - b }`): `-2`, `5`, `0`.
- Run the full diff gate to catch regressions in comparator HOFs and `String.CASE_INSENSITIVE_ORDER`:

  ```bash
  bash Scripts/diff_kotlinc.sh Scripts/diff_cases
  ```

  If parallel stdlib-artifact flakiness (`KSwiftKStdlib_0.o` / `metadata.bin not found`) appears, set `DIFF_PARALLEL=0` and rerun serially.
- Run the housekeeping checks:

  ```bash
  bash Scripts/check_todo_ids.sh
  bash Scripts/validate_runtime_abi_links.sh -Xswiftc -swift-version -Xswiftc 6
  ```
