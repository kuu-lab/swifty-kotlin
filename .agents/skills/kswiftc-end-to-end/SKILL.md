---
name: kswiftc-end-to-end
description: Verifying a kswiftc backend/stdlib change end-to-end — diff_kotlinc sample runs, LLVM IR parity against a master worktree, targeted CompilerBackendTests suites, and parity-probe pitfalls for bundled-stdlib (Char/locale/Unicode) APIs. Read this before running a backend gate; it records the harness behaviours that make a green run misleading.
---

# kswiftc End-to-End Sample & IR Parity Testing

## Devin Secrets Needed
None. Only the repo blueprint (Swift + LLVM + `kotlinc`) needs to be applied.

## When to use

A change reached Lowering, Codegen, Link, or the **bundled Kotlin stdlib**
(`Sources/CompilerCore/Stdlib/**`) and `swift test` alone is not evidence:
either the emitted IR is supposed to be unchanged (NFC refactors, pass reordering) or a
sample program's runtime output is the only thing pinning the behaviour (stdlib
migrations, ABI edits, boxing boundaries, new stdlib APIs).

Build, test, and golden-update commands and Linux environment variables
(`C_INCLUDE_PATH`, `LIBRARY_PATH`, `KSWIFTK_LLVM_DYLIB`) are in
[`AGENTS.md`](../../../AGENTS.md) — derive them from `llvm-config`, don't hardcode a
version. This file records only what AGENTS.md doesn't: the places where a green run is
misleading.

## Harness behaviours that produce false results

- **A stale binary passes.** SwiftPM incremental builds skip re-linking when a git
  checkout leaves source mtimes older than `.build/debug/kswiftc`. If a source change
  appears to have no effect, `swift package clean` before `swift build` — but only then;
  it is a several-minute cost.
- **A stale stdlib kklib silently tests the OLD stdlib.** Bundled stdlib `.kt` files are
  read at compile time from the resource bundle
  `.build/<triple>/debug/KSwiftK_CompilerCore.resources/Stdlib/` — NOT directly from
  `Sources/`. After editing `Sources/CompilerCore/Stdlib/**`, re-copy the file into the
  resource bundle AND `rm -rf ~/.cache/kswiftk/stdlib/*/KSwiftKStdlib.kklib*` before
  compiling probes (rebuild takes ~45-70s on first compile). `diff` the Sources copy
  against the bundle copy to confirm the edit actually reached the compiler.
- **`--emit llvm` and `--emit kir` are a different stdlib mode.** Using the prebuilt
  default `.kklib` requires `emit == .executable`
  ([`CompilerTypes.swift`](../../../Sources/CompilerCore/Sema/Models/CompilerTypes.swift)
  `shouldUseDefaultStdlib`), so an IR dump is always source-injection IR. It is valid for
  A/B parity against another build, but it is not the IR behind `-o <exe>`. Link and
  stdlib-resolution bugs must be reproduced in both modes.
- **`--emit kir` proves binding, not linking.** The dump shows how sema/lowering bound a
  call, but the accessor/function bodies of the *injected bundled stdlib* are not emitted
  into the user-module `.kir`. To prove the source-injection path links end-to-end,
  compile the same repro to an executable with `--stdlib-from-source` — a dangling call
  fails at link there. (Flag is a "debug fallback" in `CLIParser.swift`.)
- **`.kir` output naming.** `--emit kir -o out.kir` writes `out.kir.kir` — the extension
  is always appended. Pass `-o out` or expect the doubled suffix.
- **`.kir` call line format.** `call <linkName> symbol=<calleeName> args=[rN, rM]`.
  `linkName` is the external/mangled link name when the callee has one (e.g.
  `kk_atomic_int_create`), otherwise a module-local display name (`set`, `y`, `Box`).
  `symbol=` is the interned callee name — for property accesses it tells getter
  (`symbol=get`) from setter (`symbol=set`) and a dangling call would carry the property
  name (`symbol=value`) instead of an accessor. `kk_array_set`/`kk_array_get_inbounds`
  are direct backing-field slot accesses — their presence for a `var` write means the
  write did NOT route through an accessor.
- **Inspecting the default `.kklib` artifact.** `-o exe` uses the per-user cache bundle
  `~/.cache/kswiftk/stdlib/<ver>-<target>/KSwiftKStdlib.kklib` — a *directory* containing
  `metadata.bin`, `objects/`, `inline-kir/`, `manifest.json`. Metadata records are text:
  `strings KSwiftKStdlib.kklib/metadata.bin | grep 'setterLink='` shows serialized
  per-property fields (`getterLink=`, `setterLink=`, `recv=` for extension properties,
  `mutable=1`). Rebuilt automatically by `StdlibArtifactCache.resolveOrBuild` when the
  compiler/stdlib fingerprint changes; each `diff_kotlinc.sh` invocation also rebuilds
  its own copy under `.artifacts/diff_kotlinc/` (~1-2 min before any case runs).
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
- Keep test `.kt` repros and outputs under `/tmp` — never in the repo worktree.

## Parity-probe pitfalls for bundled-stdlib Char/locale/Unicode APIs

- **Never write `\uXXXX` Kotlin escapes through file-writing tools.** File-write paths
  may interpret the escape and store the decoded character — lone surrogates (`\uD83D`)
  cannot survive UTF-8 at all and silently become U+FFFD or a wrong code point, which
  makes the probe test the wrong character. Generate such probes with python emitting
  literal ASCII `\\uXXXX` sequences (`"'\\u%04X'" % cp`) and verify with `grep`/read-back
  that the file contains the escape text.
- **Never print `java.util.Locale` objects (or other shell stdlib classes) in a probe.**
  The bundled `java.util.Locale` has no `toString()` — printing one yields the default
  `<object 0xPTR>` rendering, which differs from kotlinc (`en_US`) AND differs between
  two runs of the same binary (non-deterministic pointer). Label sections with constant
  strings instead (`"en_US" to Locale("en","US")` pairs).
- **Case-bridge edge defects.** `__kk_char_uppercase_locale` /
  `__kk_char_lowercase_locale` NUL truncation and lone-surrogate→U+FFFD were fixed for
  Char (#7714), but the same root cause survives at String level (KUU-1216):
  `String.uppercase()`/`lowercase()`/locale variants truncate interior NULs and
  `uppercase()` maps lone surrogates to U+FFFD (JVM: identity). When a parity failure
  involves case mapping, isolate the primitive first (`uppercase(locale)` alone on the
  exact char) before attributing the bug to new code.
- **Program stdout may contain NUL/invalid-UTF-8 bytes** (e.g. `'\u0000'` results).
  `diff` then reports "Binary files differ" and hides the actual delta — compare with
  `cmp` for the verdict and `diff -a` or `xxd` for inspection.
- **Print code points, not raw chars, for risky probes.** For lone surrogates,
  unassigned code points, and noncharacters, print `.map { it.code }` lists — JVM and
  KSwiftK may diverge in the stdout *encoding* layer (replacement chars) rather than in
  the value itself; printing codes isolates value correctness and keeps the byte-compare
  meaningful.
- **A good sweep proves it isn't trivially constant.** When probing a predicate like
  `isTitleCase`, include known-positive chars (Lt: U+01C5/01C8/01CB/01F2 and Greek
  U+1F88/1F98/1FA8/1FBC/1FCC/1FFC) next to their Lu/Ll neighbours — an all-`false`
  byte-identical output would also match a broken `false`-always implementation.

## Showing CLI evidence to a human

Compiler runs are shell-only, so don't screen-record them. When a PR comment needs
visual proof, launch a terminal on the desktop and screenshot its output:
`konsole` is installed (`DISPLAY=:0 konsole -e <script>`), and
`wmctrl -i -r <winid> -b add,maximized_vert,maximized_horz` maximizes it by window ID
(`wmctrl -l` lists windows) before screenshotting with the computer tool.
If the evidence output is longer than one screen, scroll back with Shift+PageUp and take
a second screenshot of the top.

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

## Manual probe protocol (per-PR stdlib verification)

```bash
.build/debug/kswiftc /tmp/probe.kt -o /tmp/probe_out/bin   # expect exit 0, zero 'error' lines on stderr
/tmp/probe_out/bin > cand.out                            # run ELF
kotlinc /tmp/probe.kt -include-runtime -d /tmp/probe_out/ref.jar
java -XX:-UsePerfData -jar /tmp/probe_out/ref.jar > ref.out
cmp cand.out ref.out                                     # byte-identical = PASS
```

The first `kswiftc` compile after touching `Sources/CompilerCore/Stdlib/**` pays the
~45-70s kklib rebuild; subsequent compiles reuse the cache. Also run the repo's own new
diff case through `bash Scripts/diff_kotlinc.sh Scripts/diff_cases/<case>.kt` once —
it builds its own fresh artifact under `.artifacts/diff_kotlinc/` and is the sanctioned
verdict.

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
bash Scripts/swift_test.sh --no-parallel \
  --filter 'BackendDriverOutputTests|LoweringCodegenRegressionTests|VirtualDispatchCodegenTests|NameManglerTests|LinkPhaseIntegrationTests'
```

For XCTest suites, `--no-parallel` is what makes the "Executed N tests" summary
appear, so a filter that matched nothing can be told apart from a pass (see
[`AGENTS.md`](../../../AGENTS.md)). Swift Testing suites (`@Test` / `#expect`) don't print
that line either way — check the reported test count.

## Curated samples for function-resolution / IR stress

- `overload.kt` — top-level overloads by type.
- `class_and_function_same_name.kt` — class and top-level functions sharing a name.
- `extension_receiver.kt` — extension function on `Int`.
- `list_filter_is_instance.kt` — `filterIsInstance` on `List<Any>`.
- `sequence_lazy.kt` — `asSequence` / `toList` / HOF chains.
- `iterator_builder.kt` — `iterator { yield(it) }` builder.
- `coroutine_launch_join.kt` — small coroutine example.
- `collection_builders.kt` — `buildString` / `buildList` / `buildSet` / `buildMap`.
- `function_types.kt` — function-type variables and higher-order functions.

## Coroutine stdlib migrations (StateFlow / SharedFlow)

For PRs moving `StateFlow`, `MutableStateFlow`, `Flow.stateIn`, `SharedFlow`,
`MutableSharedFlow`, or `Flow.shareIn` from runtime C bridges to bundled Kotlin source:

```bash
bash Scripts/validate_runtime_abi_links.sh
bash Scripts/swift_test.sh --no-parallel --filter SmokeTests
bash Scripts/swift_test.sh --no-parallel --filter StdlibArtifactRegressionTests
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
the bundled `stateIn(initialValue:)` and `shareIn(replayCache:)` signatures differ from JVM
`kotlinx.coroutines` on purpose, so anything touching them can only be pinned by a unit
test. `state_flow_kotlin.kt` calls both and is therefore `SKIP-DIFF` (DEBT-DIFF-001).
`shared_flow_kotlin.kt` deliberately stays inside JVM-compatible API
(`MutableSharedFlow(replay)`, `tryEmit`, `replayCache`) so that it *can* be a real
`diff_kotlinc.sh` case — it carries no skip marker. Add a `shareIn` call to it and it
starts failing against `kotlinc` (loudly, per the FAIL note above); the only way it leaves
the diff gate quietly is if someone then marks it `SKIP-DIFF`.

## Probing runtime is/as/cast semantics

- **Exercise both the static and the `Any`-erased form of every `is` check.**
  `val it = expr; println(it is T)` may be folded or answered by static typing;
  only `val a: Any = expr; println(a is T)` is guaranteed to route through
  `kk_op_is` at runtime. A box whose runtime metadata is wrong will disagree with
  kotlinc on the erased form while the static form can hide the bug.
- **Verify the exception TYPE on wrong `as` casts, not just that it crashes.**
  An uncaught bad cast surfaces only as `KSwiftK panic [KSWIFTK-LINK-0003]:
  Unhandled top-level exception` — the message does not name the exception.
  Wrap the cast in `try/catch (e: ClassCastException)` to prove the thrown type
  is the kotlinc-compatible one.
- **kotlinc parity probes are cheap.** `~/tools/kotlinc/bin/kotlinc probe.kt
  -include-runtime -d /tmp/p.jar && $HOME/tools/jdk21/bin/java -jar /tmp/p.jar`
  (~30-60s) gives the JVM reference output for the exact same probe file — use
  it to pin down whether a divergence is a deliberate deviation (document it)
  or a regression. kotlinc also emits "check for instance is always 'true'"
  warnings that reveal which checks it constant-folds.
- **Pre-warm before recording.** A cold `-o exe` compile rebuilds the stdlib
  `.kklib` (~1-2 min); compile any hello.kt once first so the recorded run is
  snappy. Byte-diff program stdout against a checked-in-style `.expected` file
  in the terminal so the recording itself proves every line, not just the ones
  a viewer can eyeball.
