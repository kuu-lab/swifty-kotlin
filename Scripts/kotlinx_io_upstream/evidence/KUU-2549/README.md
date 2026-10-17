# KUU-2549 検証証跡

## 固定対象

- upstream: kotlinx-io `0.9.1`, Kotlin `2.3.10`, commit `362bdc35e159bad6da1e08101c8321792d762281`
- 原本: `core/common/test/samples/samples.kt` (`sha256=7b59c4fe909d22e75377bb89da2596f806b0f4b9390dffa3389aa3855b34436e`, Git blob `870bfa7643536a008320f4cff5a050788c1b886d`)
- 対象は issue 記載の10関数。固定実行 catalog は JVM 10件、macOS Native 10件。各結果は `reference/` と candidate lane の `results.json` に記録。
- pinned JVM と macOS arm64 Native reference は各10/10 PASS。選択 runner は原本 file 全体を保持し、指定した10の直接 no-arg method だけを呼び出す。

## Candidate matrix

検証 candidate はこの worktree の commit `c7b70e8d62bfcd5c1df891ee28d3886ae419414e`。現在の candidate compiler SHA-256 は `8a2047998a2f0d591dbdc53510a2129839e55cffaf63f9414ca5ff0105f6abb8`。source suite は原本 assertions を変更せず10件を実行した。KLIB境界の4 laneは、同じ原本から `startsWithSample` だけを選択して実行した。

| Candidate lane | 選択数 | 結果 | Compile / link / run |
|---|---:|---|---|
| source O0 | 10 | 10 PASS | 0 / — / 0 |
| source O2 | 10 | 10 PASS | 0 / — / 0 |
| stdlib-library O0 | 1 (`startsWithSample`) | 1 PASS | 0 / — / 0 |
| stdlib-library O2 | 1 (`startsWithSample`) | 1 PASS | 0 / — / 0 |
| producer-consumer O0 | 1 (`startsWithSample`) | 1 PASS | 0 / 0 / 0 |
| producer-consumer O2 | 1 (`startsWithSample`) | 1 PASS | 0 / 0 / 0 |

各 lane の summary、results、selection、compile/run commands と streams は `candidate/c7b70e8d62bfcd5c1df891ee28d3886ae419414e/` 以下にある。大きな実行ファイル、object file、KLIB binary は含めず、SHA-256 と結果 JSON は保存した。生成 stdlib の manifest SHA-256 は `ff5d1a9fd2908352ddde0cfdf2b277d95086e4c439a3613b44fb13fb1098c74d`、`metadata.bin` SHA-256 は `dd6d9584b2f42794c14930f7e4e77d4eb40d6b1538f8e9d29d3b349006a8f14c`。

## Assertion mapping と startsWith contract probe

`coverage-map.verified.json` は全10関数の元 assertion 25件、JVM/Native reference execution 20件、および current macOS Native candidate の PASS を対応付ける。`verify_gate.compose_verified_coverage` による mapping blocker は0件。seed 全体では680関数中10件が今回 verified、670件は引き続き未対応。

`contracts/startsWith-source-state-and-exceptions/` に、Source の `startsWith` が読み取り位置を消費しないこと、一致/不一致/枯渇時の戻り値、closed source の `IllegalStateException`、source failure の `IOException` 伝播を調べる直接差分 probe を保存した。candidate と Kotlin 2.3.10 reference の正規化 stdout は一致し、対象 case は PASS:

```text
true
3
1
false
2
2
true
1
3
false
0
IllegalStateException
IOException
```

## API 台帳

- `klib-78eaf273a0fd2845` (`Source.startsWith(Byte)`): API validation evidence は current candidate SHA に対する6必須 laneをすべて PASS とし、台帳上 `verified`。
- `jvm-dca5a43e89484e1c` (JVM descriptor): `javap` は pinned JVM reference のみを確認する。KSwiftK candidate は JVM bytecode を出力しないため、candidate JVM ABI を証明できず、台帳は `unverified` のまま。reference descriptor を candidate ABI 証拠として扱わない。
- KLIB row input hashes: implementation `3817278aa522307f0b70203b2bc8487bf20c768145417accd7582e363351ae50`; tests `9d4c5127acaeda09376a3710367432ddeea469ad96002b8f22573de39c6a3392`.

## Historical baseline 差分と既知 bug

Issue の初期 candidate `fd01a5e98145e8295e5b299b0a7190cc8d44e3a7` は source O0 でコンパイル exit 0 の後、最初の sample assertion 前に `RuntimeStringArray.swift:18` の `kk_array_get_inbounds precondition failed` で exit -5 となり、10件すべて NOT_RUN だった。該当する初回 `Buffer.writableSegment` runtime panic は独立した KUU-2652 の不具合で、今回重複修正していない。この worktree は修正 commit `c0856ddda21824dab76434d5a3ef0140b18f1365` (#9288) を含み、同じ10件とKLIB lanesを再実行してPASSを得た。初期 candidate の失敗証跡は `candidate/fd01a5e98145e8295e5b299b0a7190cc8d44e3a7/source-O0/` に残す。

## 実行範囲

- 実行: targeted JVM/Native reference 20件、current candidate source O0/O2 20件、`startsWithSample` KLIB source/library producer-consumer各O0/O2、1件の kotlinc differential contract probe、関連する API inventory / evidence / mapping unit checks。
- 実行した inventory/evidence checks: `python3 Scripts/io_api_inventory/generate.py --write`, `python3 Scripts/io_api_inventory/generate.py --check`, `python3 Scripts/io_api_inventory/test_reproducibility.py`, `python3 Scripts/io_api_inventory/test_validation_evidence.py`, `python3 -m unittest Scripts/kotlinx_io_upstream/tests/test_selected_reference_subset.py -v`, `python3 -m unittest Scripts/kotlinx_io_upstream/tests/test_verify_gate.py -v`, `git diff --check`。Runtime catalog の3 source hash と生成 inventory の古い local test references を現行 checkout に更新した。
- 未実行: 全 repository Swift test suite、kotlinx-io 全件 reference/diff、KSwiftK candidate の JVM bytecode/ABI lane。
