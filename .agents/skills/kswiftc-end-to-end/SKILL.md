---
name: kswiftc End-to-End Sample & IR Parity Testing
description: Verifying a kswiftc backend change end-to-end — diff_kotlinc sample runs, LLVM IR parity against a master worktree, and targeted CompilerBackendTests suites. Read this before running a backend gate; it records the harness behaviours that make a green run misleading.
---

# kswiftc End-to-End Sample & IR Parity Testing

## Devin Secrets Needed
None. Only the repo blueprint (Swift + LLVM + `kotlinc`) needs to be applied.

## When to use

A change reached Lowering, Codegen, or Link and `swift test` alone is not evidence:
either the emitted IR is supposed to be unchanged (NFC refactors, pass reordering) or a
sample program's runtime output is the only thing pinning the behaviour (stdlib
migrations, ABI edits, boxing boundaries).

Build, test, and golden-update commands are in [`CLAUDE.md`](../../../CLAUDE.md); Linux
environment variables (`C_INCLUDE_PATH`, `LIBRARY_PATH`, `KSWIFTK_LLVM_DYLIB`) are in
[`AGENTS.md`](../../../AGENTS.md) — derive them from `llvm-config`, don't hardcode a
version. This file records only what those two don't: the places where a green run is
misleading.

## Harness behaviours that produce false results

- **A stale binary passes.** SwiftPM incremental builds skip re-linking when a git
  checkout leaves source mtimes older than `.build/debug/kswiftc`. If a source change
  appears to have no effect, `swift package clean` before `swift build` — but only then;
  it is a several-minute cost.
- **`--emit llvm` and `--emit kir` are a different stdlib mode.** Using the prebuilt
  default `.kklib` requires `emit == .executable`
  ([`CompilerTypes.swift`](../../../Sources/CompilerCore/Sema/Models/CompilerTypes.swift)
  `shouldUseDefaultStdlib`), so an IR dump is always source-injection IR. It is valid for
  A/B parity against another build, but it is not the IR behind `-o <exe>`. Link and
  stdlib-resolution bugs must be reproduced in both modes.
- **`SKIP-DIFF` cases report `SKIP`, not `FAIL`.** `Scripts/diff_kotlinc.sh` skips any
  case whose source carries `// SKIP-DIFF` or `// KSWIFTK_DIFF_IGNORE`; the reason and
  debt ID belong in that comment and in
  [`docs/diff-skip-inventory.md`](../../../docs/diff-skip-inventory.md). Use
  `--force-run-skipped` to check whether a skip has quietly become stale.
- **A `FAIL` can mean your case is broken, not the compiler.** When `kotlinc` and
  `kswiftc` both fail to compile with the same exit code, the harness now forces a `FAIL`
  rather than treating matching exit codes as parity, and prints both sides' compile
  stderr. Read that stderr before assuming a regression — invalid Kotlin in the case
  itself looks identical at the verdict line.
- **JDK 17 is not JDK 21.** `diff_kotlinc.sh` requires JDK 21 by default; set
  `DIFF_REQUIRE_JDK21=0` to run under 17. `Float`/`Double` `toString()` formatting
  differs between the two, so restrict that mode to integer/string cases.
- **Coroutine cases reach the network.** `diff_kotlinc.sh` downloads
  `kotlinx-coroutines-core-jvm` for any case importing `kotlinx.coroutines`. When Maven
  is unavailable or rate-limited, pass a local jar via `KOTLINC_CLASSPATH` instead.
- `swift test --filter` takes a regex; the specifier is `Target.SuiteName/testName`, so a
  bare suite name works. If a `|` regex is rejected, run the suites separately.
- If `/tmp` fills up, point `TMPDIR` at a writable directory with space.

## Run a single diff sample

```bash
DIFF_REQUIRE_JDK21=0 bash Scripts/diff_kotlinc.sh --no-parallel --run-timeout 30 \
  Scripts/diff_cases/hello.kt
```

Expected: `PASS Scripts/diff_cases/hello.kt`.

The full `Scripts/diff_cases` directory is ~1425 cases and parallelises across
`DIFF_WORKERS` (default: CPU count). It prints nothing until each case finishes — delegate
the whole-directory gate to CI or a long-running job and run a targeted subset
interactively.

## LLVM IR parity against master

Keep both branches built side-by-side in a worktree:

```bash
git worktree add ../swifty-kotlin-master master
(cd ../swifty-kotlin-master && swift build)
.build/debug/kswiftc --emit llvm -o "${TMPDIR:-/tmp}/pr.ll" Scripts/diff_cases/hello.kt
../swifty-kotlin-master/.build/debug/kswiftc --emit llvm -o "${TMPDIR:-/tmp}/master.ll" \
  Scripts/diff_cases/hello.kt
diff -u "${TMPDIR:-/tmp}/master.ll" "${TMPDIR:-/tmp}/pr.ll"
```

Expected: empty diff. Both sides are source-injection IR (see above).

## Targeted CompilerBackendTests suites

```bash
SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh \
  --filter 'BackendDriverOutputTests|LoweringCodegenRegressionTests|VirtualDispatchCodegenTests|NameManglerTests|LinkPhaseIntegrationTests'
```

For XCTest suites, `SWIFT_TEST_PARALLEL=0` is what makes the "Executed N tests" summary
appear, so a filter that matched nothing can be told apart from a pass (see
[`CLAUDE.md`](../../../CLAUDE.md)). Swift Testing suites (`@Test` / `#expect`) don't print
that line either way — check the reported test count.

## Curated samples for function-resolution / IR stress

- `overload.kt` — top-level overloads by type.
- `class_and_function_same_name.kt` — class and top-level functions sharing a name.
- `extension_receiver.kt` — extension function on `Int`.
- `list_filter_is_instance.kt` — `filterIsInstance` on `List<Any>`.
- `sequence_lazy.kt` — `asSequence` / `toList` / HOF chains.
- `iterator_builder.kt` — `iterator { yield(...) }` builder.
- `coroutine_launch_join.kt` — small coroutine example.
- `collection_builders.kt` — `buildString` / `buildList` / `buildSet` / `buildMap`.
- `function_types.kt` — function-type variables and higher-order functions.

## Coroutine stdlib migrations (StateFlow / SharedFlow)

For PRs moving `StateFlow`, `MutableStateFlow`, `Flow.stateIn`, `SharedFlow`,
`MutableSharedFlow`, or `Flow.shareIn` from runtime C bridges to bundled Kotlin source:

```bash
bash Scripts/validate_runtime_abi_links.sh
SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --filter SmokeTests
SWIFT_TEST_PARALLEL=0 bash Scripts/swift_test.sh --filter StdlibArtifactRegressionTests
```

`validate_runtime_abi_links.sh` confirms removed `kk_*` bridges no longer break ABI
validation; it forwards its arguments to `swift_test.sh`, so `-Xswiftc -swift-version
-Xswiftc 6` works for matching CI's language mode.

`StdlibArtifactRegressionTests` already owns the expected stdout — read it there rather
than copying it into a PR description or a note.
`testStateFlowThroughSharedStdlibArtifact` embeds the same program as
`Scripts/diff_cases/state_flow_kotlin.kt`;
`testSharedFlowThroughSharedStdlibArtifact` is broader than
`shared_flow_kotlin.kt` and also covers `collect` and `shareIn`. Both live in
[`StdlibArtifactRegressionTests.swift`](../../../Tests/CompilerBackendTests/StdlibArtifactRegressionTests.swift)
and exercise the shared-`.kklib` path that `diff_kotlinc.sh` uses.

The split between the unit tests and the diff cases is deliberate, so don't "fix" it:
the bundled `stateIn(initialValue:)` and `shareIn(replay:)` signatures differ from JVM
`kotlinx.coroutines` on purpose, so anything touching them can only be pinned by a unit
test. `state_flow_kotlin.kt` calls both and is therefore `SKIP-DIFF` (DEBT-DIFF-001).
`shared_flow_kotlin.kt` deliberately stays inside JVM-compatible API
(`MutableSharedFlow(replay)`, `tryEmit`, `replayCache`) so that it *can* be a real
`diff_kotlinc.sh` case — it carries no skip marker. Add a `shareIn` call to it and it
starts failing against `kotlinc` (loudly, per the FAIL note above); the only way it leaves
the diff gate quietly is if someone then marks it `SKIP-DIFF`.
