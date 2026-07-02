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
loc_by_directory	.	731
loc_by_directory	.github	488
loc_by_directory	.vscode	24
loc_by_directory	Scripts	21545
loc_by_directory	Sources	313089
loc_by_directory	Stdlib	3783
loc_by_directory	Tests	223662
loc_by_directory	docs	2291
header_helpers_synthetic_total_lines	Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift	82606
kk_literal_count	Swift/Kotlin sources	15653
interner_resolve_literal_comparison_count	Swift sources	694
```

Notes:
- `loc_by_directory` counts physical lines in git-tracked files, grouped by top-level directory.
- `kk_literal_count` counts Swift/Kotlin string literals beginning with `"kk_`.

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
