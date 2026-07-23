# Refactoring Metrics

Baseline refreshed on 2026-07-12 for the RF-GOV-002 state that publishes `Scripts/loc_report.sh` as a CI artifact.

## LoC Guard

Command:

```bash
bash Scripts/loc_report.sh
```

Output:

```tsv
metric	scope	value
loc_by_directory	.	2695
loc_by_directory	.github	737
loc_by_directory	Scripts	22591
loc_by_directory	Sources	328534
loc_by_directory	Stdlib	3617
loc_by_directory	Tests	231961
loc_by_directory	docs	3472
loc_by_path_prefix	Sources/CompilerCore/Sema/DataFlow	93496
loc_by_path_prefix	Sources/CompilerCore/Sema/TypeCheck	35644
header_helpers_synthetic_total_lines	Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift	77223
call_lowerer_legacy_total_lines	Sources/CompilerCore/KIR/CallLowerer+Legacy*.swift	4028
kir_lowering_todo_fixme_count	Sources/CompilerCore/{KIR,Lowering}/*.swift	0
kk_literal_count	Swift/Kotlin sources	17199
interner_resolve_literal_comparison_count	Swift sources	716
typecheck_interner_resolve_literal_comparison_count	Sources/CompilerCore/Sema/TypeCheck	105
```

Notes:
- `loc_by_directory` counts physical lines in git-tracked files, grouped by top-level directory.
- `loc_by_path_prefix` tracks phase-specific line-count targets that are too coarse at top-level directory granularity.
- `kk_literal_count` counts Swift/Kotlin string literals beginning with `"kk_`.
- `kir_lowering_todo_fixme_count` counts remaining `TODO` / `FIXME` markers in `Sources/CompilerCore/KIR/*.swift` and `Sources/CompilerCore/Lowering/*.swift`.
- `call_lowerer_legacy_total_lines` and `typecheck_interner_resolve_literal_comparison_count` track RF4 reduction goals directly.

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

## Bundled Stdlib Injection Cost

Captured on 2026-07-23 with a debug `kswiftc` build on Linux (x86_64).

Display path:
- `Driver.finalizeRun` calls `PhaseTimer.printSummary()` when `-Xfrontend time-phases` is present.
- `PhaseTimer.phaseRecords` stores phase records and their subrecords; `printSummary()` renders the `bundled-stdlib` subrecords recorded by `Lex` and `Parse`.

Command:

```bash
bash Scripts/measure_bundled_stdlib_injection.sh 5
```

Bundled stdlib injection cost is defined here as `Lex bundled-stdlib + Parse bundled-stdlib`.

| Run | Lex bundled-stdlib (ms) | Parse bundled-stdlib (ms) | Total (ms) |
|---:|---:|---:|---:|
| 1 | 29.00 | 6.94 | 35.94 |
| 2 | 28.27 | 7.58 | 35.85 |
| 3 | 28.83 | 7.97 | 36.80 |
| 4 | 28.22 | 9.39 | 37.61 |
| 5 | 28.06 | 7.78 | 35.84 |

Median bundled stdlib injection cost: **36.05 ms**.

Cache work trigger: start bundled stdlib caching when the same local/debug measurement regresses by **+100 ms** or more from this baseline, i.e. median total `>= 136.05 ms`. RF-STDLIB-006 did not add the `IncrementalCompilationCache` pre-parse path because the measured overhead is below the trigger.

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
