# Refactoring Metrics

Baseline refreshed on 2026-08-14 for the RF-GOV-002 state that publishes `Scripts/loc_report.sh` as a CI artifact.

## LoC Guard

Command:

```bash
bash Scripts/loc_report.sh
```

`loc_report.sh` itself is compatible with macOS's system Bash 3.2 and uses
Python 3 for the syntax-aware name-dispatch metrics. Other scripts under
`Scripts/` may require Bash 4+.

The KSP-691 task note captured `__kk_` 390 / `kk_` 1,770 on 2026-08-12;
this table is the current post-fetch baseline after subsequent master changes.

Output:

```tsv
metric	scope	value
loc_by_directory	.	862
loc_by_directory	.agents	167
loc_by_directory	.github	783
loc_by_directory	Scripts	28895
loc_by_directory	Sources	298413
loc_by_directory	Tests	250891
loc_by_directory	docs	3592
loc_by_path_prefix	Sources/CompilerCore/Sema/DataFlow	68998
loc_by_path_prefix	Sources/CompilerCore/Sema/TypeCheck	36986
header_helpers_synthetic_total_lines	Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift	50298
call_lowerer_legacy_total_lines	Sources/CompilerCore/KIR/CallLowerer+Legacy*.swift	3182
kir_lowering_todo_fixme_count	Sources/CompilerCore/{KIR,Lowering}/*.swift	0
kk_literal_count	Swift/Kotlin sources	9104
kk_cdecl_count	Sources/Runtime/@_cdecl("kk_*")	1582
__kk_cdecl_count	Sources/Runtime/@_cdecl("__kk_*")	463
interner_resolve_literal_comparison_count	Swift sources	728
typecheck_interner_resolve_literal_comparison_count	Sources/CompilerCore/Sema/TypeCheck	78
typecheck_string_literal_switch_case_count	Sources/CompilerCore/Sema/TypeCheck/*.swift	402
typecheck_inline_string_set_entry_count	Sources/CompilerCore/Sema/TypeCheck/*.swift	142
```

Notes:
- `loc_by_directory` counts physical lines in git-tracked files, grouped by top-level directory.
- `loc_by_path_prefix` tracks phase-specific line-count targets that are too coarse at top-level directory granularity.
- `kk_literal_count` counts Swift/Kotlin string literals beginning with `"kk_`.
- `kk_cdecl_count` counts distinct `@_cdecl("kk_...")` names in tracked Swift files under `Sources/Runtime/`.
- `__kk_cdecl_count` counts distinct `@_cdecl("__kk_...")` names in the same scope. These two metrics count bridge definitions only; they do not count references, `RuntimeABISpec` entries, generated files, fixtures, docs, or arbitrary string literals.
- `kir_lowering_todo_fixme_count` counts remaining `TODO` / `FIXME` markers in `Sources/CompilerCore/KIR/*.swift` and `Sources/CompilerCore/Lowering/*.swift`.
- `call_lowerer_legacy_total_lines` and `typecheck_interner_resolve_literal_comparison_count` track RF4 reduction goals directly.

## Name Dispatch Metrics

ARCH-022 adds two syntax-aware metrics for the remaining name-based Sema
dispatch surface. The scanner reads tracked Swift files under
`Sources/CompilerCore/Sema/TypeCheck/` and removes comments before tokenizing,
so examples in documentation or comments do not inflate the count.

| Metric | Definition | Baseline (2026-09-08) |
|---|---|---:|
| `typecheck_string_literal_switch_case_count` | `case` clauses whose first pattern token is a string literal; a clause with multiple comma-separated literals counts once | 402 |
| `typecheck_inline_string_set_entry_count` | Direct string literal elements in explicit `Set<String> = [...]` array literals; non-literal expressions and nested arrays are excluded | 142 |

The baseline was measured at base revision `a72cc373f859aaf408c6a4e9510404a1e21c92dc`
with:

```bash
bash Scripts/loc_report.sh
```

The scanner honors the hash count in extended string delimiters and skips
quoted strings nested inside interpolation expressions, so string contents do
not create false `case` or table-entry matches. The fixture is parsed with
`swiftc -parse` before its metric assertions run.

The scanner regression fixture covers nested comments, string contents,
multiline type formatting, inline comments, multiple table entries, and a
non-string switch case:

```bash
bash Scripts/test_loc_report.sh
```

If the Python scanner cannot run, `loc_report.sh` exits nonzero instead of
emitting a successful-looking metric row.

CI publishes the same TSV from the `refactoring-metrics` job as artifact `refactoring-metrics-${run_id}` and mirrors it into the job summary.

## KIR + Lowering TODO/FIXME Triage

RF3/RF4 後の `KIR + Lowering` 実測では、残存 marker は 4 件でした。RF-LOWER-002 の `CollectionLiteralLoweringPass+PreScan.swift` 単純名分類 TODO、RF-LOWER-003 の sequence plus/minus 共通化、DEBT-KIR-001 の safe-call virtual dispatch 再有効化は修正済みで、guard metric の現在値は 0 件です。

| Classification | Count | Items |
|---|---:|---|
| Resolved | 4 | `CollectionLiteralLoweringPass+PreScan.swift` の stdlib type 判定を FQN ベースへ変更、RF-LOWER-003 の sequence plus/minus 共通化 2 件、DEBT-KIR-001 の safe-call virtual dispatch 再有効化 1 件 |
| Taskized | 0 | なし |
| Delete | 0 | 削除のみで閉じられる marker はなし |

## jscpd Guard

Report-only command used for the combined `.jscpd.json` baseline:

```bash
jscpd --config .jscpd.json --silent --reporters json --output /tmp/kswiftk-jscpd-report --exitCode 0
```

Combined `Sources/` + `Tests/` result:

| Metric | Value |
|---|---:|
| Files | 1522 |
| Lines | 329178 |
| Clones | 3516 |
| Duplicated lines | 40795 |
| Duplicated line % | 12.39% |
| Duplicated tokens | 441450 |
| Duplicated token % | 14.30% |

Tests-only observation with the same `minLines=5` / `minTokens=50` settings:

| Metric | Value |
|---|---:|
| Files | 999 |
| Lines | 159829 |
| Clones | 2089 |
| Duplicated lines | 22163 |
| Duplicated line % | 13.87% |
| Duplicated tokens | 254999 |
| Duplicated token % | 16.55% |

The CI observation step is report-only. Set a Tests-specific threshold after enough runs confirm a stable target.

## Compiler Sub-phase Timing

`kswiftc -Xfrontend time-phases` prints nested, inclusive wall-clock timings
under the existing top-level phases. Labels are printed in full, including long
validation and lowering pass names. `TOTAL` and percentages still use only the
sum of top-level phase durations; do not add sub-phase durations to `TOTAL`.

- **Sema:** DataFlowSema and TypeCheckSema, with bundled-index construction,
  import loading, early header predeclaration, imported stdlib index merge,
  synthetic registration, deferred import work, header collection, every
  validation pass, and body analysis nested under DataFlowSema.
- **Imports:** `indexDecode` measures the indexed metadata cache lookup or
  read/decode; `registerShells` measures compact-index shell registration.
  `imports.lazyMaterialize` accumulates demanded signature/body-record
  materialization and binding work in the top-level phase where it actually
  runs, including later BuildKIR or Lowerings work. Recursive materializations
  are counted once. This inclusive subtotal overlaps other scopes and is not
  an additional phase. No timing forces an unused declaration to materialize.
- **Lowerings:** one record for each pass, in `executedLowerings` order,
  including stage checks and feature-gated skips.
- **Codegen:** backend `init`, `prepareMetadata`, `initEmitter`, KIR-to-LLVM `emit`, target-machine
  `initTarget`, LLVM `opt`, and output `write`. LLVM IR at O0 omits `opt` and
  `initTarget` because those operations are skipped. Object `write` includes
  LLVM's native object emission. Library exports also record
  `writeLibraryMetadata` for inline KIR, manifest and metadata serialization.
- **Link:** library object discovery, runtime object resolution, entry wrapper,
  autolink stub preparation and the existing `Link/swiftc` driver invocation.

Timing scopes record elapsed work even if that work throws. Without a phase
timer, the scopes execute their body directly without reading the clock,
building timing labels or allocating timing records.

## Bundled Stdlib Injection Cost

The injection cost is the paired full-phase difference, not one bundled-source
subtotal:

```text
source-injected TOTAL - --no-stdlib TOTAL
```

Both commands use the same compiler binary, input, `--emit kir` mode, and
`-Xfrontend time-phases` flag. `TOTAL` is the sum of the `PhaseTimer` phase
records for that mode. The script computes one difference per pair and uses the
median of those differences as the baseline. The `Lex`/`Parse`
`bundled-stdlib` subrecords remain in the report as a diagnostic breakdown; they
are not the injection-cost definition. The probe is the stdlib-independent
[`Scripts/measurement_cases/bundled_stdlib_injection.kt`](../Scripts/measurement_cases/bundled_stdlib_injection.kt),
so the same source can complete under plain `--no-stdlib`.

Controlled baseline captured on 2026-09-08 from base
`a72cc373f859aaf408c6a4e9510404a1e21c92dc`:

```bash
KSWIFTC=/private/tmp/swifty-todo-state001-base/.build/debug/kswiftc \
  /opt/homebrew/bin/bash Scripts/measure_bundled_stdlib_injection.sh 5
```

The exact-base debug compiler is SHA-256
`ab80c404d9a82f2b63df4b6659984995bd5d80ac187df8f238847038441ae54b`. The
measurement ran on macOS 27.0 (Darwin 27.0, arm64), Apple Swift 6.4, and GNU
Bash 5.3. The script's portable wall-clock helper used `/usr/bin/python3`
3.9.6; the exclusive batch coordinator used `/opt/homebrew/bin/python3`
3.14.7. The five paired runs were executed baseline first and source-injected
second under the batch's exclusive benchmark lock.

| Run | Source-injected TOTAL (ms) | `--no-stdlib` TOTAL (ms) | Difference (ms) | Lex bundled-stdlib (ms) | Parse bundled-stdlib (ms) |
|---:|---:|---:|---:|---:|---:|
| 1 | 3700.97 | 216.39 | 3484.58 | 178.30 | 24.35 |
| 2 | 3661.40 | 206.19 | 3455.21 | 179.30 | 22.63 |
| 3 | 3674.87 | 202.60 | 3472.27 | 176.72 | 22.56 |
| 4 | 3682.46 | 202.35 | 3480.11 | 183.46 | 21.28 |
| 5 | 3648.78 | 200.28 | 3448.50 | 169.18 | 21.12 |

The full-phase injection baseline is **3472.27 ms** (paired-difference range
**3448.50–3484.58 ms**). The cache work trigger remains a regression of
**+100.00 ms** or more from this baseline, so the trigger for this matched
compiler/input/options tuple is median paired difference **≥ 3572.27 ms**.
Re-measure the baseline when the compiler binary, input, emit mode, or frontend
flags change; the absolute threshold is not portable across those changes.

The same script also reports the stdlib-only `.kklib` build time and the shared
candidate compile time for `hello.kt` with
`--no-stdlib --stdlib-library <artifact>`. Those are a separate wall-clock
check for the shared diff path and do not enter the injection-cost baseline.

## Migration API Runtime Benchmark

KSP-INF-007 baseline captured on 2026-07-23 with a debug `kswiftc` build on Linux (x86_64).

Command:

```bash
bash Scripts/benchmark_stdlib_hof.sh
```

The harness compiles each Kotlin source in `Scripts/benchmark_cases/` with `kswiftc` and reports the median wall-clock execution time over 7 runs.

| Case | Workload | Median (ms) |
|---|---|---:|
| filter | `(1..100000).filter { it > 50000 }.sum()` | 63 |
| map | `(1..100000).map { it * 2 }.sum()` | 111 |
| sort | `(1..100000).toList().sorted().first()` | 94 |
| for_in_range | `for (i in 1..1000000) sum += i` | 1236 |

These numbers are the reference for "performance reasons to keep Swift residuals". Any migration of stdlib internals to Swift must beat the relevant baseline.

## Compact `.kklib` index observation (KUU-2051)

2026-10-14, baseline master `d2e74c5d1136d94a32bd140f1cda32371800e506`,
debug build, Apple Swift 6.4, macOS 27 arm64. Both compilers generated a fresh
stdlib artifact. The artifacts each contain 31,457 records; their UTF-8 record
bodies are byte-identical (SHA-256
`e308907999daa449c8993a4b666e3b4b4f15a70413ddb43582314ac551ebf2b0`).
The change replaces only the eager text index with the v3 fixed table/string
pool described in Doc J14 of `spec.md`.

After excluding the first runtime build and warming the filesystem/runtime
cache, two alternating before/after `hello.kt` executable compilations gave:

| Warm pair | v2 indexDecode (ms) | v3 indexDecode (ms) | Before TOTAL (ms) | After TOTAL (ms) |
|---|---:|---:|---:|---:|
| 1 | 2310.01 | 145.20 | 8889.06 | 6568.21 |
| 2 | 2023.25 | 103.48 | 8361.79 | 5895.38 |
| Median | 2166.63 | 124.34 | 8625.43 | 6231.80 |

This is approximately 94% less index decode time and 28% less TOTAL in this
small sample. Other builds/tests were active on the host; early contended runs
varied substantially. These measurements do not establish an LSP latency or
large-program compilation speedup. Every executable printed exactly `hello`.

Reproduce with separate before/after compiler binaries and fresh artifacts:

```bash
<compiler> --stdlib-only --emit library -o /tmp/stdlib-<variant>
<compiler> Scripts/diff_cases/hello.kt --stdlib-library /tmp/stdlib-<variant>.kklib \
  -Xfrontend time-phases -o /tmp/hello-<variant>
/tmp/hello-<variant>
```

The v3 string pool contains 69,242 strings. The indexed prefix grows from
7,526,971 to 7,774,704 bytes (+3.3%); `metadata.bin` grows from 17,761,991 to
18,009,724 bytes (+1.4%). This is the storage cost of fixed-width entries in
this corpus. Compactness refers to the shell shape and positional fields;
the format avoids per-record text tokenization, key/value dispatch, and full
MetadataRecord construction at library discovery.

## Parallel compact index decode observation (KUU-2679)

2026-10-20, baseline master `9940cc7550`, debug build, Apple Swift 6.4, macOS
27 arm64. The v3 format is unchanged; `CompactMetadataIndex.decode` now scans
string byte ranges sequentially, then decodes the string pool and the
fixed-width entry table in per-core chunks via
`DispatchQueue.concurrentPerform`, concatenating chunk results in file order.
Malformed input still rejects the whole file identically. The probe reuses
the KUU-2051 stdlib artifact shape (31,457 records, 69,242 pooled strings,
`metadata.bin` ≈ 18 MB).

An early low-contention window gave `indexDecode` ≈ 104–115 ms baseline and
≈ 34–42 ms parallel (~3×). A later interleaved A/B while the host was
saturated by other builds (load average ≈ 250–320) inflated both compilers
roughly 6× but kept the ratio:

| Warm pair | Sequential indexDecode (ms) | Parallel indexDecode (ms) |
|---:|---:|---:|
| 1 | 384.51 | 342.40 |
| 2 | 1024.61 | 165.88 |
| 3 | 1186.13 | 540.51 |
| 4 | 618.03 | 248.63 |
| 5 | 698.96 | 134.12 |
| Median | 698.96 | 248.63 |

Both windows agree on ≈ 2.8–3× less index decode time (~65–70 ms absolute on
an idle host, ~3% of a `hello.kt` debug TOTAL). These measurements do not
establish a release-mode or LSP latency speedup.

Reproduce with separate before/after compiler binaries sharing one artifact:

```bash
<compiler> Scripts/diff_cases/hello.kt --no-stdlib \
  --stdlib-library /tmp/stdlib.kklib -Xfrontend time-phases -o /tmp/hello
```
