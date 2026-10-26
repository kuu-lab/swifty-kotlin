# Scripts workflow

## Inventory

| Script | CI | Purpose |
|---|---|---|
| `swift_test.sh` | ✓ | `swift test` wrapper: parallel defaults, grouped failure summary, golden-update hint, GitHub annotations, crash-signal retry |
| `swift_build.sh` | – | Coordinate focused local `swift build` invocations with test builds across worktrees |
| `summarize_stdlib_timings.py` | – | Summarize opt-in stdlib artifact build durations and overlap across processes |
| `shard_swift_tests.sh` | ✓ | Split one slow test target across CI jobs (`--mode dynamic` per-test / `--mode static` per-suite) |
| `js_annotations/run_ci.py` | ✓ | JVM-independent annotation/view/reflection source/artifact O0/O2 matrix, runner regressions, and KUU-1480 evidence; see [handoff](../docs/js-annotations-ci-evidence.md) |
| `diff_kotlinc.sh` | ✓ | Behavioral diff of `kswiftc` vs `kotlinc` over `diff_cases/`, plus candidate-only output checks for target-specific cases; persists failure artifacts |
| `real_programs/run.py` | – | Run the [23 pinned public Kotlin consumers](real_programs/round1/README.md) against Kotlin 2.3.10 and native O0/O2 with one fresh shared stdlib; compare exit code, stdout, and stderr |
| `run_candidate_only.sh` | ✓ | Compile one Kotlin case without a JVM reference and compare stdout with its `.expected` file |
| `diff_diagnostics.sh` | ✓ | Diagnostic differential over `diagnostic_cases/`: compile acceptance and normalized error line sets |
| `diff_kotlinc_ci_summary.sh` | ✓ | Render the diff TSV report as a markdown step summary with embedded diffs |
| `loc_report.sh` | – | Refactoring guard metrics as TSV (LoC by directory, `kk_` literals, TODO/FIXME counts) |
| `dead_code_audit.sh` | – | Audit `@_cdecl kk_*` runtime symbols unreachable from the compiler |
| `benchmark_stdlib_hof.sh` | – | Runtime micro-benchmark harness over `benchmark_cases/` (median wall-clock per case) |
| `test_all.sh` | ✓ | Run every `Scripts/test_*.sh` regression test and summarize; new `test_*.sh` files are picked up automatically |
| `check_todo_ids.sh` | ✓ | Detect duplicate task IDs in `TODO.md` |
| `check_mutation_fuzzer_keywords.sh` | ✓ | Verify `mutate_diff_cases.py`'s `IDENTIFIER_KEYWORDS` matches the lexer's `Keyword` enum |
| `check_workflow_npm_install.sh` | ✓ | Forbid ad-hoc `npm install`/`npx`/etc. in GitHub workflows/actions — npm-based CI tools go through `.github/ci-tools/` lockfile + `npm ci --ignore-scripts` |
| `validate_runtime_abi_links.sh` | – | Shorthand for the `RuntimeABIExternalLinkValidationTests` filter |
| `validate_jvm_stdlib.py` | – | Check Kotlin class/member references in repository-built JVM stdlib and consumer JARs; see [JVM stdlib](../docs/jvm-stdlib.md) |
| `check_atomicfu_api_reference.py` | – | Verify the pinned kotlinx.atomicfu 0.33.0 KLIB/JVM snapshots, target-aware declaration index, and unsupported API names |
| `generate_atomicfu_api_index.py` | – | Build the deterministic per-declaration common/native API ledger with source provenance, visibility, overloads, and annotations (`--output PATH` writes it for inspection) |
| `lib/common.sh` | (sourced) | Shared helpers: worker detection, interleaved sharding, filter chunking, case-name sanitizing, diff-tooling preflight, case-directive parsing, artifact-collision avoidance |

## swift_test.sh

`Scripts/swift_test.sh` wraps `swift test` with parallel execution enabled by default.

- Tune XCTest and Swift Testing workers (including Golden): `SWIFT_TEST_WORKERS=4 bash Scripts/swift_test.sh`
- Tune build jobs: `SWIFT_TEST_BUILD_JOBS=4 bash Scripts/swift_test.sh`
- Tune concurrent local builds across worktrees: `SWIFT_BUILD_SLOTS=2 bash Scripts/swift_test.sh`
- Disable parallel mode: `bash Scripts/swift_test.sh --no-parallel`

`SWIFT_TEST_WORKERS` must be a positive integer. Explicit Swift Testing
`--experimental-maximum-parallelization-width` or
`SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH` settings take precedence for
Swift Testing. Without a worker override, the runner keeps its default width.
Limiting workers reduces concurrent CPU load; it does not skip test cases.

For a focused test, anchor and escape the module prefix when it is known:

```bash
bash Scripts/swift_test.sh --filter '^CompilerCoreTests\.SuiteName/testName' --no-parallel
```

When `swiftbuild` is selected, the wrapper automatically selects the single
test product for this anchored form. It also detects a toolchain whose default
build system is `swiftbuild`. Ambiguous regexes, unanchored filters, native
builds, and `--skip-build` are left unchanged because narrowing them could omit
tests or select a product that was not built. `SWIFT_TEST_PRODUCT` or an
explicit `--test-product` overrides automatic selection.

Before building, a single simple `Module.Suite` or `Module.Suite/test` filter
is checked against the suite and method declarations in that test target's
Swift sources. Both unanchored and anchored forms are supported. This is a
source-level check, not SwiftPM test discovery; complex regexes are left to
SwiftPM. If a test is
generated or inherited and cannot be found this way, set
`SWIFT_TEST_SOURCE_PREFLIGHT=0`. If SwiftPM reports that a filtered run matched
no tests, the wrapper fails instead of reporting success. For an existing,
up-to-date test build, `swift test list --skip-build` can show the registered
names; it must not be used as evidence for changes that have not been built.

Locally, `swift_test.sh` and `swift_build.sh` share a limit of two SwiftPM
builds at a time across worktrees and divide detected build jobs between those
slots. Use the build wrapper for focused builds so it participates in the same
limit, for example `bash Scripts/swift_build.sh --product kswiftc`. The slot is released
as soon as SwiftPM reports `Build complete!`, so a slow test does not occupy a
build slot. `SWIFT_BUILD_SLOTS` changes the limit; `0` disables it.
`SWIFT_TEST_BUILD_JOBS` for tests, `SWIFT_BUILD_JOBS` for builds, and explicit
`-j`/`--jobs` take precedence over the automatic per-build job count. CI keeps
its existing behavior unless slots are explicitly configured. `--skip-build`
does not acquire a slot. The shared slot
directory defaults to `/tmp/kswiftk-swift-build-slots-<uid>` and can be
overridden with `SWIFT_BUILD_SLOT_DIR`; all cooperating worktrees must use
the same directory and slot count. If Python 3 is unavailable, the wrapper
warns and skips the cross-worktree limit. Direct `swift build`, `swift test`,
and other scripts do not participate in the limit. If SwiftPM does not emit
its normal build-complete marker, the slot remains held until it exits.

To reduce Golden and other frontend test CPU time locally, build CompilerCore
with the same debug optimization setting used by CI:

```bash
KSWIFTK_OPTIMIZE_COMPILER_CORE=1 SWIFT_TEST_WORKERS=4 bash Scripts/swift_test.sh --filter Golden
```

This opts CompilerCore into `-O` while keeping the debug build configuration.
It can make stepping through CompilerCore code less direct; omit the setting
when debugging the compiler. Run without `--skip-build` when changing it so
the compiler is rebuilt with the requested optimization level.

To measure overlapping stdlib artifact builds across worktrees, set the same
`KSWIFTK_STDLIB_TIMINGS` path for the test or compiler processes under study:

```bash
KSWIFTK_STDLIB_TIMINGS=/tmp/kswiftk-stdlib-timings.jsonl bash Scripts/swift_test.sh --filter '<test>'
python3 Scripts/summarize_stdlib_timings.py /tmp/kswiftk-stdlib-timings.jsonl
```

The opt-in JSONL log records start/end events for in-process artifact builders
and `kswiftc --stdlib-only`, including elapsed time and success. It does not
record source paths or change cache behavior. The summary reports completed,
failed, incomplete and invalid spans, peak overlap, and duration percentiles.
An interrupted process can leave an incomplete span; overlap counts use only
completed spans. Wall-clock changes can invalidate an interval. Logging is
best-effort and the parent directory must already exist. Keep the file in a
private location when collecting measurements from concurrent worktrees.

If a run crashes with a signal (e.g. `*** Signal 11: ...` / `exited with
unexpected signal code`) and no per-test failure line was parsed, the whole
`swift test` invocation is retried up to 3 times before failing the step.
This targets swift-corelibs-foundation's Linux `Process.run()` races that
`CommandRunner.processLaunchLock` cannot fully close (unrelated threads in
the same xctest process can still mutate the fd table mid-spawn); genuine
test failures are never retried, since they always produce a parsed failure.

When you are iterating on test failures after a successful build, you can also
reuse the existing build products:

```bash
bash Scripts/swift_test.sh --skip-build
```

### macOS toolchain requirement (XCTest)

Testing requires a toolchain that ships XCTest: full Xcode on macOS, or any
Linux Swift toolchain. The macOS **Command Line Tools alone are not enough** —
with `xcode-select` pointing at them, `swift test` first rejects the
auto-added `--num-workers` with a misleading `'--num-workers' is only
supported when testing with XCTest` (independent of `--filter`), and test
files importing XCTest cannot build at all. `swift_test.sh` probes the active
toolchain (`xcrun --find xctest`) and fails fast with instructions. Fix
either way:

```bash
sudo xcode-select -s /Applications/Xcode.app
# or per-invocation:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Scripts/swift_test.sh ...
```

## Candidate-only diff cases

Some cases have no JVM `kotlinc` reference target. Mark these in the Kotlin
source with `// DIFF_CANDIDATE_ONLY_FROM_SOURCE`, add a sibling `.expected`
file or ordered `// EXPECT-STDOUT:` lines containing the expected stdout,
then run the case without kotlinc or a JDK reference. The
candidate compiles bundled stdlib sources with the case rather than using a
precompiled artifact, preserving internal source-backed declarations:

```bash
bash Scripts/diff_kotlinc.sh --candidate-only Scripts/diff_cases/stdlib_kotlin_concurrent_AtomicIntArray_n_n.kt
```

Regular differential runs execute these cases in the same source mode, in
both serial and parallel runs. The separate `run_candidate_only.sh` lane
continues to own `// CANDIDATE-ONLY` cases with `.expected.stdout` or
`.expected.stderr` sidecars. Run `bash Scripts/test_diff_kotlinc_candidate_from_source.sh`
to verify discovery, source compilation, and exclusion from that lane.

## Runtime ABI link validation

Validate compiler runtime link names against `RuntimeABISpec`:

```bash
bash Scripts/validate_runtime_abi_links.sh
```

## Atomicfu API reference

Verify the pinned 0.33.0 upstream ABI snapshots, generated per-declaration
index, exact pinned source bytes, declaration annotation arguments and visibility,
effective KLIB target scopes, and excluded `compareAndExchange` / `load`
/ `store` / `MemoryOrder` names:

```bash
python3 Scripts/check_atomicfu_api_reference.py
```

The 155-row ABI-identity index (150 common/native declarations plus five
explicitly excluded inherited JS/Wasm identities; the common/native declarations
span 126 unique rendered signatures) is built in memory from the pinned
`atomicfu.klib.api` by every consumer, so no copy is checked in. The schema-2
index separates direct, enclosing and file annotations. All Native rows have
verified source evidence; the five excluded JS/Wasm rows explicitly keep unknown
annotation facts because that target source is unavailable. Source registration and runtime requirements remain unfinished:

```bash
python3 Scripts/generate_atomicfu_api_index.py --output /tmp/atomicfu-index.json
python3 Tests/Scripts/test_atomicfu_api_index.py
```

## TODO hygiene

Detect duplicate task IDs in `TODO.md`:

```bash
bash Scripts/check_todo_ids.sh
```

## Mutation fuzzer keyword drift check

`Scripts/mutate_diff_cases.py` classifies scanned tokens as `keyword` vs.
`identifier` using its own `IDENTIFIER_KEYWORDS` set, kept independent of the
Swift lexer for simplicity. Verify it still matches the hard-keyword
`Keyword` enum in `Sources/CompilerCore/Lexer/TokenModel.swift`:

```bash
bash Scripts/check_mutation_fuzzer_keywords.sh
```

Soft keywords (`SoftKeyword` enum, e.g. `by`, `get`, `value`) are
deliberately excluded from this comparison — they are valid identifiers in
most contexts, so treating them as keywords would misclassify real
identifier usages in the seed corpus.

## Golden update workflow

1. Run only the affected golden suite without updating fixtures. For example,
   for a Sema change:

```bash
bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden
```

2. Review differences:

```bash
git diff -- Tests/CompilerCoreTests/GoldenCases
```

3. If the change is intentional, update the same affected suite
   (the `-swift-version` flags match the CI language mode):

```bash
UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden -Xswiftc -swift-version -Xswiftc 6
```

   The Golden tests run `GoldenHarnessWorker` from `./.build/debug/` of the
   current directory (or `$GOLDEN_HARNESS_WORKER`), **not** from a
   `--scratch-path` build. When you build into a separate scratch path, point
   `GOLDEN_HARNESS_WORKER` at that build's worker; otherwise the stale worker
   cannot read the freshly built stdlib artifact, silently falls back to
   source mode, and `UPDATE_GOLDEN=1` rewrites hundreds of goldens with broken
   output.

4. Re-review fixture changes and ensure only intended files changed:

```bash
git status --short
git diff -- Tests/CompilerCoreTests/GoldenCases
```

5. Re-run the affected golden suite with the CI language mode and any focused
   regression tests needed for the change. Run an individual kotlinc diff case
   when parity is relevant. The full test and diff suites belong in CI unless
   explicitly requested or needed to reproduce a CI failure. Use the Lexer,
   Parser, Sema, or Diagnostics suite type name appropriate to the change; the
   full `--filter Golden` is for changes spanning multiple suites.

### Golden stability (after harness / concurrency changes)

Golden tests run each case in a dedicated worker process so `swift test --parallel` can fan them out safely. To sanity-check flakiness after harness changes, run the filter twice (or more):

```bash
bash Scripts/swift_test.sh --filter Golden
bash Scripts/swift_test.sh --filter Golden
```

## Candidate-only Kotlin cases

Cases under `Scripts/candidate_cases/` do not use the JVM `kotlinc` reference.
The runner compiles the case and any supplied support sources into one
candidate module, runs the native executable, and diffs stdout with the
adjacent `.expected` file:

```bash
bash Scripts/run_candidate_only.sh \
  Scripts/candidate_cases/logging_basic.kt \
  Scripts/candidate_cases/support/slf4j_minimal.kt
```

The runner reuses `.artifacts/diff_kotlinc/KSwiftKStdlib.kklib` when present.
Set `KSWIFTK_STDLIB_LIBRARY` to reuse another prebuilt artifact.

## kotlinc diff workflow

Run one case:

```bash
bash Scripts/diff_kotlinc.sh Scripts/diff_cases/hello.kt
```

The stdlib artifact build has its own 600-second timeout, independent of the
120-second per-case compile timeout. Override it with `--stdlib-timeout <seconds>`
or `DIFF_STDLIB_COMPILE_TIMEOUT`; a timeout is reported separately from a
compiler failure. The same setting is forwarded to candidate-only runs.

For a case without a JVM reference target, add
`// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: <sidecar-filename>` to the `.kt` file
and store its expected stdout in a regular sidecar file beside the source. The
harness compiles and runs that case with `kswiftc` and compares stdout to the
sidecar. A direct invocation of that case does not require or invoke kotlinc or
Java; a directory run uses this
mode only for marked cases and keeps the JVM comparison for other cases.

Run all tracked regression cases:

```bash
bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

Cases that cannot use the JVM reference compiler can opt into candidate-only
execution with `// DIFF_CANDIDATE_ONLY` and exactly one
`// DIFF_EXPECT_STDOUT: <expected line>` directive. The harness compiles and runs
the case with `kswiftc`, then compares stdout (with a trailing newline) against
the expected line. It does not invoke `kotlinc` or `java` when every selected
case is candidate-only; in a mixed run, those tools are used only by the other
cases. Run a candidate-only file directly to verify it without JVM tooling:

```bash
bash Scripts/diff_kotlinc.sh Scripts/diff_cases/stdlib_kotlin_native_concurrent_ThreadLocal_n_n.kt
```

For the audited `js_annotations.kt` migration, use the dedicated native lane:

```bash
KSWIFTK_OPTIMIZE_COMPILER_CORE=1 swift build --product kswiftc
KOTLINC=/not-used JAVA_BIN=/not-used python3 Scripts/js_annotations/run_ci.py
```

Pass `--kswiftc .build/out/Products/Debug/kswiftc` for the Xcode build layout.
This runs all 27 native fixtures across source injection/fresh `.kklib` and
O0/O2, preserving failures, timeouts, and unexecuted cases in evidence artifacts.
PR CI owns the fast runner regressions; `nightly-full.yml` owns the real matrix
in `verify-js-annotations`. See [runner commands](js_annotations/README.md) and
[coverage and SKIP-removal handoff](../docs/js-annotations-ci-evidence.md). The current
SKIP remains until the full evidence is ready; this does not run the JVM diff.

`diff_kotlinc.sh` detects imports in the target file or recursively in a target
directory and downloads JVM reference jars from Maven Central:

| Import | Artifact | Default version |
|---|---|---|
| `kotlinx.coroutines` | `kotlinx-coroutines-core-jvm` | 1.10.2 |
| `kotlinx.io` | `kotlinx-io-core-jvm` | 0.9.1 |
| `kotlinx.io.bytestring` | Both io core and `kotlinx-io-bytestring-jvm` | 0.9.1 |
| `kotlinx.atomicfu` | `atomicfu-jvm` | 0.33.0 |

Cases using multiple libraries receive all their dependencies, including
atomicfu wildcard, individual, and alias imports. This import
detection is the equivalent of a `requires_kotlinx_io` header; no extra header
is needed. An explicit `--kotlinc-classpath` / `KOTLINC_CLASSPATH` bypasses all
automatic downloads, so supply every required jar in that classpath.
Cases using only fully qualified atomicfu expressions can supply the pinned
jar with `--kotlinc-classpath`.
You can control the cached path and version with:

```bash
export KOTLINC_COROUTINES_VERSION=1.10.2
export KOTLINC_KOTLINX_IO_VERSION=0.9.1
export KOTLINC_ATOMICFU_VERSION=0.33.0
export KOTLINC_DEP_DIR=/path/to/.runtime-build/deps
```

Downloads are checksum-verified. For versions without a checksum baked into
the script, also set:

```bash
export KOTLINC_COROUTINES_SHA256=<expected sha256 of the jar>
export KOTLINC_KOTLINX_IO_SHA256=<expected sha256 of the io core jar>
export KOTLINC_KOTLINX_IO_BYTESTRING_SHA256=<expected sha256 of the bytestring jar>
export KOTLINC_ATOMICFU_SHA256=<expected sha256 of the atomicfu jar>
```

Override individual cached paths with `KOTLINC_COROUTINES_JAR`,
`KOTLINC_KOTLINX_IO_JAR`, `KOTLINC_KOTLINX_IO_BYTESTRING_JAR`, and
`KOTLINC_ATOMICFU_JAR`.
Run `bash Scripts/test_diff_kotlinc_dependencies.sh` to check dependency
selection without downloading jars or building the compiler.

The atomicfu reference is the real Maven Central `atomicfu-jvm:0.33.0` jar,
SHA-256 `cdc94bfe4f739a0121860e61977d5c1e6a3d53c21f2471493393ba9e900d394e`.
Unknown versions require an explicit checksum. Both downloaded and cached jars
are verified before use. The scalar reference runs without the atomicfu plugin:

```bash
atomicfu_jar=/path/to/atomicfu-jvm-0.33.0.jar
printf '%s  %s\n' cdc94bfe4f739a0121860e61977d5c1e6a3d53c21f2471493393ba9e900d394e "$atomicfu_jar" | sha256sum -c
kotlinc Scripts/reference_cases/atomicfu_scalar.kt -classpath "$atomicfu_jar" -include-runtime -d /tmp/atomicfu-reference.jar
java -cp "/tmp/atomicfu-reference.jar:$atomicfu_jar" Atomicfu_scalarKt > /tmp/atomicfu-reference.out
diff -u Scripts/reference_cases/atomicfu_scalar.expected /tmp/atomicfu-reference.out
```

This reference fixture is outside `diff_cases`: candidate-side atomicfu support
has its own implementation tickets. A reference pass does not establish
KSwiftK atomic behavior or Kotlin/Native compatibility.

For the separately pinned Kotlin/Native 2.3.10 / atomicfu 0.33.0 Linux/x64
reference, including Native Trace no-op, lock aliases, parking and exception
differences, see [atomicfu_native_reference/README.md](atomicfu_native_reference/README.md).

A case can use `// DIFF_EXPECTED_OUTPUT: <relative-path>` when kotlinc is not a
usable oracle. The runner compiles and runs only kswiftc, then compares stdout
to that fixture. When the target is this single case, JVM tooling is not
required; directory runs still configure JVM tooling for their ordinary diff
cases.

Successful non-script reference compilations are reused across runs via
`KOTLINC_REF_CACHE_DIR` (default: `.runtime-build/kotlinc-ref-cache`, so a
second full run skips the per-case kotlinc compile entirely). Set it to
another directory to relocate the cache, or to empty to disable:

```bash
KOTLINC_REF_CACHE_DIR=/tmp/kswiftk-kotlinc-refs \
  bash Scripts/diff_kotlinc.sh Scripts/diff_cases   # relocate
KOTLINC_REF_CACHE_DIR= \
  bash Scripts/diff_kotlinc.sh Scripts/diff_cases   # disable
```

Each cached jar is keyed by the source name and contents, extra compiler
flags, Kotlin compiler version, JDK version, and classpath contents.
Script-style cases still execute through `kotlinc -script` on every run.
Note that `--clean-runtime-cache` removes `.runtime-build` and therefore
also the default reference cache. It also clears the runtime-object cache shared across worktrees
(`~/Library/Caches/kswiftk/runtime-build`, or `$KSWIFTK_RUNTIME_CACHE_DIR`).

kotlinc invocations run with `-XX:TieredStopAtLevel=1` (C1-only JIT,
~15-20% faster for these short-lived compiles) prepended to `JAVA_OPTS`;
caller-provided `JAVA_OPTS` flags still win on conflict. Override or
disable with `DIFF_KOTLINC_JAVA_OPTS` (empty disables). The plain `java`
runs of reference jars are unaffected (`java` does not read `JAVA_OPTS`).
Reference `java` runs disable HotSpot perf-data collection by default with
`-XX:-UsePerfData`, preventing parallel CI workers from turning a locked
`hsperfdata` diagnostic into a false stdout mismatch. Override with
`DIFF_REFERENCE_JAVA_FLAGS` (set it empty to disable the default).

Emit a machine-readable report (TSV) for CI tooling:

```bash
bash Scripts/diff_kotlinc.sh --report /tmp/diff_report.tsv Scripts/diff_cases
```

Omit `PASS` lines in logs (CI uses `DIFF_LOG_PASS=0`):

```bash
DIFF_LOG_PASS=0 bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

Pass additional arguments to each candidate `kswiftc` invocation with
`DIFF_KSWIFTC_FLAGS`. The per-shard stdlib artifact remains at the default
optimization level, while the case under test receives these flags; CI uses
this to keep the baseline and optimized lanes separate:

```bash
DIFF_KSWIFTC_FLAGS="-O2" bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

In CI, the diff corpus (at both `-O0` and `-O2`) runs only in the daily full
verification, `.github/workflows/nightly-full.yml`; pull requests and the merge
queue do not run it. Trigger that workflow with `workflow_dispatch` on a branch
to run the corpus before merging.

### Backend diff lanes (JVM / WASM)

`DIFF_BACKEND` (or `--backend`) switches the candidate side to a different
backend while the kotlinc/JVM reference stays unchanged:

```bash
DIFF_BACKEND=jvm   bash Scripts/diff_kotlinc.sh Scripts/diff_cases
DIFF_BACKEND=wasm DIFF_ENGINE=node     bash Scripts/diff_kotlinc.sh Scripts/diff_cases
DIFF_BACKEND=wasm DIFF_ENGINE=wasmtime bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

Directory sweeps are opt-in per case: only files carrying `// DIFF_JVM`
(resp. `// DIFF_WASM`) run in that lane; everything else reports
`SKIP ... (DIFF_BACKEND=...)`, and a sweep that ends up running zero cases
fails instead of reporting a vacuous pass. Naming a single `.kt` file runs
it without a marker. Candidate-only case kinds (`DIFF_CANDIDATE_ONLY*`,
`CANDIDATE-ONLY`, `DIFF_CANDIDATE_ONLY_FROM_SOURCE`) stay native-only.

- `jvm` compiles each case with `--emit jar --classpath <jvm stdlib jar>` and
  runs `java -Xverify:all -cp case.jar:stdlib.jar <Main-Class>` (the class is
  read from the candidate jar manifest). The shared stdlib jar is built once
  per run under `DIFF_ARTIFACT_ROOT` (reuse an existing one with
  `DIFF_JVM_STDLIB_JAR`).
- `wasm` compiles each case with `--target wasm32-wasi` (override via
  `DIFF_WASM_TARGET`; the bundled stdlib still compiles from source inline)
  and runs the module through `DIFF_ENGINE`: `node` (node:wasi via
  `Scripts/wasi_node_runner.mjs`) or `wasmtime` (`wasmtime run`). Engine
  binaries resolve from `NODE_BIN` / `WASMTIME_BIN`.

Nightly runs both lanes: `verify-jvm-diff` and `verify-wasm` (a per-engine
`node`/`wasmtime` matrix).

You can control parallel execution. The worker count is set by `--jobs <n>`
(or the equivalent `DIFF_WORKERS` env var); `0` means serial. By default the
script runs in parallel with one worker per CPU:

```bash
# Set the worker count explicitly (0 = serial)
bash Scripts/diff_kotlinc.sh --jobs 4 Scripts/diff_cases
DIFF_WORKERS=4 bash Scripts/diff_kotlinc.sh Scripts/diff_cases

# Disable parallel execution
bash Scripts/diff_kotlinc.sh --no-parallel Scripts/diff_cases
DIFF_PARALLEL=0 bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

`DIFF_PARALLEL` is a boolean toggle (`0` = serial, `1` = parallel, the
default). Setting it to a number greater than 1 is deprecated — it prints a
warning and is treated as `DIFF_WORKERS`.

`DIFF_WORKERS` parallelizes within one machine. To split the case
set across several machines (CI shards the regression this way; the current
shard count is the diff-regression matrix in `.github/workflows/nightly-full.yml`),
use interleaved sharding — case `i` runs only when `i % count == index`:

```bash
# 4 shards; each prints/reports only its ~1/4 of the cases.
DIFF_SHARD_INDEX=0 DIFF_SHARD_COUNT=4 bash Scripts/diff_kotlinc.sh Scripts/diff_cases
DIFF_SHARD_INDEX=1 DIFF_SHARD_COUNT=4 bash Scripts/diff_kotlinc.sh Scripts/diff_cases
# ...and shards 2, 3 on other machines. Combine with --jobs for per-machine parallelism.

# Equivalent flags
bash Scripts/diff_kotlinc.sh --shard-index 0 --shard-count 4 Scripts/diff_cases
```

Sharding and `DIFF_WORKERS` compose: a shard still runs its slice across the
configured workers. `DIFF_SHARD_COUNT=1` (the default) disables sharding.

Render a markdown summary from that report:

```bash
bash Scripts/diff_kotlinc_ci_summary.sh --report /tmp/diff_report.tsv --summary /tmp/step_summary.md
```

## Diagnostic differential workflow

`diff_diagnostics.sh` is the first-stage diagnostic oracle. It compares only
whether `kotlinc` and `kswiftc` accept the source and, when both reject it, the
normalized set of source line numbers containing an error diagnostic. Diagnostic
wording and diagnostic codes are deliberately outside this contract.

The dedicated `Scripts/diagnostic_cases/` directory keeps negative cases out of
the behavioral `diff_kotlinc.sh` run. Use `// EXPECT-REJECT` for a case that
must be rejected by both compilers; acceptance is the default and can be stated
explicitly with `// EXPECT-ACCEPT`.

A case may pass extra flags to `kotlinc` with `// KOTLINC_FLAGS: <flags>`.
Fixtures are treated as untrusted input: the flag list is validated against an
allowlist of language-feature and diagnostic toggles (e.g. `-Xfeature`,
`-Xfeature=mode`, `-XXLanguage:+Feature`, `-jvm-target 21`, `-opt-in=<fqname>`)
before `kotlinc` runs. Options that load JVM code or reshape the compiler
environment — `-Xplugin`, plugin `-P`, `-J`, `@argfile`, `-classpath` and
friends — fail the case without invoking the compiler.

```bash
bash Scripts/diff_diagnostics.sh Scripts/diagnostic_cases
bash Scripts/diff_diagnostics.sh --report /tmp/diagnostics.tsv Scripts/diagnostic_cases
bash Scripts/diff_diagnostics.sh --self-test
```

The harness requires JDK 21 or newer by default, matching the CI Kotlin 2.4.20
lane. For local toolchains that are intentionally different, set
`DIFF_REQUIRE_JDK21=0` and record that limitation with the result.

Cases marked `// DIFF_CANDIDATE_ONLY` bypass kotlinc compilation and execution.
Add one `// DIFF_EXPECT_OUTPUT: <line>` directive for each expected stdout line;
repeated directives represent multiline output, and an empty directive represents
an empty line. The candidate must compile, exit successfully, and match those
lines exactly. This path is for cases where a JVM reference target cannot model
the input, such as same-module `expect`/`actual` declarations.

## Precompiled stdlib artifact for diff runs

`diff_kotlinc.sh` builds a shared stdlib `.kklib` once per shard and references it from
each candidate compile. The artifact is created under `DIFF_ARTIFACT_ROOT` (default
`.artifacts/diff_kotlinc/KSwiftKStdlib.kklib`) at runtime and is never committed.

```bash
# Default: build artifact automatically and use it for all cases
bash Scripts/diff_kotlinc.sh Scripts/diff_cases

# Reuse an existing artifact (useful for local debugging or repro scripts)
DIFF_STDLIB_LIBRARY=/path/to/KSwiftKStdlib.kklib bash Scripts/diff_kotlinc.sh Scripts/diff_cases
bash Scripts/diff_kotlinc.sh --stdlib-library /path/to/KSwiftKStdlib.kklib Scripts/diff_cases

# Build a stdlib artifact manually
.build/debug/kswiftc --stdlib-only --emit library -o /tmp/KSwiftKStdlib.kklib
# Then compile a user file against it
.build/debug/kswiftc --no-stdlib --stdlib-library /tmp/KSwiftKStdlib.kklib Scripts/diff_cases/hello.kt -o /tmp/hello
```

The artifact manifest records `libraryKind: stdlib` and `stdlibManifestHash` so
mismatched compiler/stdlib versions are rejected with `KSWIFTK-LIB-0021` / `KSWIFTK-LIB-0022`.

## CI test sharding

`shard_swift_tests.sh` splits one test target across several CI jobs using the
same interleaved rule as `diff_kotlinc.sh` sharding. XCTest and Swift Testing
targets can shard documented test specifiers per method (`--mode dynamic`,
backed by `swift test list`); targets that cannot be listed reliably can shard
per-suite with source-estimated test weights (`--mode static`, backed by source
scanning). Dynamic mode can exclude suites that need separate execution:

```bash
bash Scripts/shard_swift_tests.sh --mode dynamic --list-filter '^CompilerBackendTests\.' \
  --shard-index 0 --shard-count 6
bash Scripts/shard_swift_tests.sh --mode dynamic --list-filter '^CompilerCoreTests\.' \
  --list-exclude '^CompilerCoreTests\.(FrontendParallelBenchmarkTests|SmokeTests)/' \
  --target-prefix CompilerCoreTests \
  --shard-index 0 --shard-count 6
bash Scripts/shard_swift_tests.sh --mode static --tests-dir Tests/RuntimeTests \
  --target-prefix RuntimeTests
```

## Refactoring guard metrics

`loc_report.sh` emits the metrics used as the RF-series refactor gate,
including phase-target path counts for Sema/DataFlow, TypeCheck, and legacy
CallLowerer files (see `docs/refactoring-metrics.md` for the tracked baseline
and CI artifact name):

```bash
bash Scripts/loc_report.sh > after.tsv
```

## Dead-code audit

`dead_code_audit.sh` lists `@_cdecl kk_*` runtime symbols that no compiler
path can emit (run with `--help` for the exclusion pipeline; retained symbols and
their reason codes are tracked in `docs/dead-code-audit.md`):

```bash
bash Scripts/dead_code_audit.sh --verbose
```

The `Quarterly Audits` workflow runs this audit with the fiction audit on the
first day of January, April, July, and October. Its summary and the intermediate
audit files are retained as a 90-day GitHub Actions artifact.

## Ktor build probe

`ktor_build.sh` sparse-clones pinned snapshots of Ktor's core `common` source
sets (`ktor-io`, `ktor-utils`, `ktor-http`) and their kotlinx-io dependency
into a cache dir outside the repo, compiles each with `kswiftc --emit
library`, and writes a per-module TSV of diagnostic-code counts (see
`docs/ktor-build-status.md` for the current gap inventory). It is a
diagnostic probe, not a CI-wired regression test — a module failing to
compile is expected until the remaining gaps close.

```bash
bash Scripts/ktor_build.sh                  # fetch + compile all modules
bash Scripts/ktor_build.sh --no-fetch        # reuse an existing checkout
bash Scripts/ktor_build.sh --module ktor_io  # compile a single module
```

## diff_run_interpreter.sh

`kswiftc --run`（KIR インタプリタ、未対応プログラムは native へフォールバック）と、通常コンパイルした実行ファイルの stdout / 終了コードを比較する。ケースごとに `[interpreted]` か `[fallback (理由)]` を表示する。

```bash
bash Scripts/diff_run_interpreter.sh Scripts/diff_cases/hello.kt [more.kt ...]
```

インタプリタが扱うのは Int / Boolean / String、制御フロー、ユーザー関数呼び出し、トップレベル変数、`print`/`println` のみ（`Sources/CompilerCore/Driver/KIRInterpreter.swift`）。それ以外の runtime / stdlib 呼び出しは実行前の静的解析でフォールバックし、0 除算・深い再帰など値依存の脱出は出力をバッファしたまま native 再実行へ切り替える。
