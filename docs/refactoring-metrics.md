# Refactoring Metrics

Baseline captured on 2026-07-02 for the RF-GUARD state that includes this document and `Scripts/loc_report.sh`.

## LoC Guard

Command:

```bash
bash Scripts/loc_report.sh
```

Output:

```tsv
metric	scope	value
loc_by_directory	.	741
loc_by_directory	.github	488
loc_by_directory	Scripts	21553
loc_by_directory	Sources	313343
loc_by_directory	Stdlib	3783
loc_by_directory	Tests	223920
loc_by_directory	docs	3009
header_helpers_synthetic_total_lines	Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift	82624
kir_lowering_todo_fixme_count	Sources/CompilerCore/{KIR,Lowering}/*.swift	3
kk_literal_count	Swift/Kotlin sources	15624
interner_resolve_literal_comparison_count	Swift sources	692
```

Notes:
- `loc_by_directory` counts physical lines in git-tracked files, grouped by top-level directory.
- `kk_literal_count` counts Swift/Kotlin string literals beginning with `"kk_`.
- `kir_lowering_todo_fixme_count` counts remaining `TODO` / `FIXME` markers in `Sources/CompilerCore/KIR/*.swift` and `Sources/CompilerCore/Lowering/*.swift`.

## KIR + Lowering TODO/FIXME Triage

RF3/RF4 後の `KIR + Lowering` 実測では、残存 marker は 4 件でした。RF-LOWER-002 の `CollectionLiteralLoweringPass+PreScan.swift` 単純名分類 TODO は即修正し、guard metric の現在値は 3 件です。

| Classification | Count | Items |
|---|---:|---|
| Immediate fix | 1 | `CollectionLiteralLoweringPass+PreScan.swift` の stdlib type 判定を FQN ベースへ変更 |
| Taskized | 3 | RF-LOWER-003 の sequence plus/minus 共通化 2 件、DEBT-KIR-001 の safe-call virtual dispatch 再有効化 1 件 |
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

Captured on 2026-07-03 for KSP-007 with a debug `kswiftc` build on macOS.

Display path:
- `Driver.finalizeRun` calls `PhaseTimer.printSummary()` when `-Xfrontend time-phases` is present.
- `PhaseTimer.phaseRecords` stores phase records and their subrecords; `printSummary()` renders the `bundled-stdlib` subrecords recorded by `Lex` and `Parse`.

Command:

```bash
.build/debug/kswiftc Scripts/diff_cases/hello.kt -o /tmp/ksp_out -Xfrontend time-phases
```

Bundled stdlib injection cost is defined here as `Lex bundled-stdlib + Parse bundled-stdlib`.

| Run | Lex bundled-stdlib (ms) | Parse bundled-stdlib (ms) | Total (ms) |
|---:|---:|---:|---:|
| 1 | 19.37 | 3.58 | 22.95 |
| 2 | 14.80 | 3.30 | 18.10 |
| 3 | 14.27 | 2.99 | 17.26 |

Median bundled stdlib injection cost: **18.10 ms**.

Cache work trigger: start bundled stdlib caching when the same local/debug measurement regresses by **+100 ms** or more from this baseline, i.e. median total `>= 118.10 ms`.
