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
loc_by_directory	.	768
loc_by_directory	.github	488
loc_by_directory	.vscode	24
loc_by_directory	Scripts	21545
loc_by_directory	Sources	313290
loc_by_directory	Stdlib	3783
loc_by_directory	Tests	223832
loc_by_directory	docs	2168
header_helpers_synthetic_total_lines	Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift	82977
kk_literal_count	Swift/Kotlin sources	15675
interner_resolve_literal_comparison_count	Swift sources	0
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
| Files | 1527 |
| Lines | 329513 |
| Clones | 3526 |
| Duplicated lines | 40895 |
| Duplicated line % | 12.41% |
| Duplicated tokens | 442317 |
| Duplicated token % | 14.31% |

Tests-only observation with the same `minLines=5` / `minTokens=50` settings:

| Metric | Value |
|---|---:|
| Files | 1001 |
| Lines | 159997 |
| Clones | 2093 |
| Duplicated lines | 22202 |
| Duplicated line % | 13.88% |
| Duplicated tokens | 255395 |
| Duplicated token % | 16.55% |

The CI observation step is report-only. Set a Tests-specific threshold after enough runs confirm a stable target.
