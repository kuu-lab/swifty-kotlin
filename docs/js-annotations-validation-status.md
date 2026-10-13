# js_annotations 独立検証の集約 (KUU-1603)

確認日: 2026-10-13 JST。親: [KUU-1603](https://linear.app/kuu/issue/KUU-1603)。
確認対象 checkout: `ce8daf2824533c14d4d2d513193bd5538166dc62`。
契約は [Kotlin 2.3.10 監査](js-annotations-contract-2.3.10.md)、
期待値と reference provenance は [監査 fixture](fixtures/js_annotations/README.md) を参照。

親の完了判定は **未完了**。7子チケットのうち6件は Done / PR merged、
KUU-1617 は In Progress。KUU-1616 の PR は2026-10-13 08:12 JSTに merged を確認した。
source/artifact 間の一致だけでは期待契約の成立を意味しない。
失敗のある matrix を SKIP 解除 evidence として採用しない。
各子の実装は `1子チケット = 1 task = 1 branch = 1 PR` で維持する。

## 子チケットと証拠

| 子チケット | 担当する証拠 | Linear / GitHub の確認結果 |
|---|---|---|
| [KUU-1604](https://linear.app/kuu/issue/KUU-1604) | 2.3.10 契約、valid/negative fixture、reference provenance | Done / [#8051](https://github.com/kuu-lab/swifty-kotlin/pull/8051) merged |
| [KUU-1612](https://linear.app/kuu/issue/KUU-1612) | JVM 非依存 runner、出力/診断/終了コード/timeout 比較 | Done / [#8072](https://github.com/kuu-lab/swifty-kotlin/pull/8072) merged |
| [KUU-1613](https://linear.app/kuu/issue/KUU-1613) | file/export/static の focused Sema matrix | Done / [#8240](https://github.com/kuu-lab/swifty-kotlin/pull/8240) merged |
| [KUU-1614](https://linear.app/kuu/issue/KUU-1614) | collection view の共有 backing、copy、型/readonly | Done / [#8273](https://github.com/kuu-lab/swifty-kotlin/pull/8273) merged |
| [KUU-1615](https://linear.app/kuu/issue/KUU-1615) | constructor/default/副作用/失敗経路 | Done / [#8329](https://github.com/kuu-lab/swifty-kotlin/pull/8329) merged |
| [KUU-1616](https://linear.app/kuu/issue/KUU-1616) | source injection / 新規 .kklib × O0/O2 | Done / [#8751](https://github.com/kuu-lab/swifty-kotlin/pull/8751) merged、保存全 matrix は fail |
| [KUU-1617](https://linear.app/kuu/issue/KUU-1617) | 専用 CI 接続、全 coverage と解除手順 | In Progress、先行する KUU-1616 は Done |

Done は各子の限定した完了範囲を示す。全 fixture の native 契約成立を示すものではない。

## source/artifact matrix の保存結果

以下は PR #8751 の最終 head `69c7f15cf9340f1042200b6bf0084622b34fd6f4` に保存された
記録を確認した結果であり、この親ブランチでの compiler 再実行ではない。
記録内の source revision と PR head は区別する。

| 記録 | source/O0 | source/O2 | .kklib/O0 | .kklib/O2 | 総合 |
|---|---|---|---|---|---|
| [全27 fixture](https://github.com/kuu-lab/swifty-kotlin/blob/69c7f15cf9340f1042200b6bf0084622b34fd6f4/docs/fixtures/js_annotations/evidence/native-matrix-results.json) | 14 pass / 13 fail | 14 pass / 13 fail | 14 pass / 13 fail | 14 pass / 13 fail | 56 pass / 52 fail、対象外3件 |
| [reflection の3 fixture](https://github.com/kuu-lab/swifty-kotlin/blob/69c7f15cf9340f1042200b6bf0084622b34fd6f4/docs/fixtures/js_annotations/evidence/create-instance-postfix-matrix-results.json) | 3 pass | 3 pass | 3 pass | 3 pass | 12 pass、対象外0件 |

全 matrix の run ID は `20261012T174726.291593Z-627f1c59`、記録 source revision は
`d9ae31cbcfbf0cc634fa5b57e506228069903a48`。compiler SHA-256 は
`902a5a49442e951f5032be01a0cce3affc886a4b671265b00bc1361e3bbb0e55`、
新規 artifact tree SHA-256 は
`1a89d1c1f68d52e8daeafca763eb750297b2e797f0f5fcae97ae5994018baca7`。
27 fixture の4経路間に不一致はないが、13 fixture は4経路とも失敗する。

focused run ID は `20261012T223347.330419Z-ae59f9e8`、記録 source revision は
`abe4179d9bfdf9ec501c10c749ad2fc19c8ddda3`。compiler SHA-256 は
`93062a552f8602ec026bd85544b98106f102d6b325bfa70c96262ce0b365e5d0`、
新規 artifact tree SHA-256 は
`01878a9059a57625713eed16bc7bddd4abca9eb6c7055d13247f03ae08f435aa`。
対象は `unbound_create_instance`, `reflection`, `native_observations`。
両記録の toolchain は Apple Swift 6.4、arm64 macOS 27.0。
これは Linux CI / Swift 6.3 の実行証拠ではない。

### 残る13 fixture

| fixture | 全 matrix に保存された失敗理由 |
|---|---|
| `annotation_arguments` | annotation 引数個数の candidate code / expected kind が未マップ |
| `bare_create_instance` | `KSWIFTK-SEMA-0022` が未マップ |
| `collection_imports` | `UNRESOLVED_IMPORT` が未マップ、診断 multiset 不一致 |
| `collection_marker_fqn` | 期待 compile exit 1 に対し実測0、定数性診断の不足/未マップ |
| `export_nonexportable` | non-exportable type の candidate code / expected kind が未マップ |
| `export_suspend` | wrong declaration の candidate code / expected kind が未マップ |
| `file_name_arguments` | argument type の candidate code / expected kind が未マップ |
| `file_name_nonconstant` | const の candidate code / expected kind が未マップ |
| `file_name_target` | target の candidate code / expected kind が未マップ |
| `marker_as_file` | arity / target の candidate code / expected kind が未マップ |
| `marker_no_opt_in` | 期待 warning 3件に対し実測2件 |
| `static_receivers` | companion 制約の candidate code / expected kind が未マップ |
| `static_visibility_const` | visibility / const 制約の candidate code / expected kind が未マップ |

未マップ診断の解消は根拠のある adapter 対応で行う。
不足する診断や終了コードの不一致は adapter の追加だけでは解消しない。
期待値を candidate の現状へ緩和して通過させない。
`collection_imports` の既存追跡先 [KUU-1736](https://linear.app/kuu/issue/KUU-1736) は
[view matrix の注記](fixtures/js_annotations/views/README.md) を参照。

## 原ケースからの coverage 対応

| 原ケースの用法・観測 | 移行先 | 対象と現在の制限 |
|---|---|---|
| file name / file marker / opt-in | `file_name_no_opt_in`, `file_name_arguments`, `file_name_nonconstant`, `file_name_target`, `marker_as_file`, `no_opt_in`、`JsFileNameAnnotationTests` | native 診断/metadata。全 matrix には未マップ診断が残る。JS の生成 file 名は reference lane |
| export marker / static marker / `js-annotations` | `marker_requirements`, `marker_no_opt_in`, `static_accepted`, `native_observations`、`JsExportAnnotationTests`, `JsStaticAnnotationTests` | marker と emission を分離。marker warning の不足が残る。JS export/static は `.mjs` consumer の reference lane |
| view import / marker FQN | `collection_imports`, `collection_marker_fqn` | 無効用法を拒否する契約。全 matrix は fail |
| Map/Set/array の `2:3:4` | `native_observations`, `typed_views`, `views_map`, `views_set`, `views_readonly_array` | native の有効 conversion API で数を観測。コピー・固定 size・backing 変更の欠落も検出 |
| view の typed `.size` / `.length` / mutator / variance | `typed_view_properties`, `views_typed_mutators`, `views_variance` | 公開されていない typed 操作を拒否。JS の相互変更・readonly 書き込み拒否は `views_dynamic` reference lane |
| 裸 `::createInstance` | `bare_create_instance` | 無効入力の診断。native adapter 未マップ |
| `ExportedBox:createInstance:7` | `native_observations`, `reflection`、PR #8751 の `unbound_create_instance` | bound name / direct default / typed-unbound generic 戻り値。focused 12セルは pass |
| constructor 選択/既定値の副作用/候補0個・複数 | `reflection`、`kotlinJsCreateInstanceUsesSharedConstructorPath` | native の例外文字列は `nativeContract`、JS reference の文字列と分離 |

移行先は監査 fixture と focused Swift tests を専用 runner/CI で継続する方式。
無効 import や公開されていない typed property を持つ原ケースを、そのまま runtime oracle にしない。
JS emission / dynamic JS の reference 証拠を KSwiftK native 成功件数へ含めない。

## CI の現在地と次の完了条件

`ci.yml` は repository checks / build / SmokeTests、`nightly-full.yml` は
CompilerCore/Backend の Swift tests と candidate-only diff を実行する。
focused Swift tests は nightly の target 選択に含まれるが、
`Scripts/js_annotations/run_candidate.py` と PR #8751 の `run_matrix.py` を直接呼ぶ接続はない。
target の設定だけを専用 matrix が CI で実行済みの証拠として扱わない。

1. KUU-1617 で13 fixture の失敗の所有先を確定する。診断 adapter と製品契約の不足を区別し、各担当で解消した後、同一 revision の全 matrix を再採取する。
2. KUU-1617 の独立 task/branch/PR で runner 回帰、source/artifact × O0/O2、artifact 保存を CI に接続する。KUU-1616 の Done / merged を全 matrix 成功の証拠として扱わない。
3. CI run URL、commit/toolchain/hash、stdout/stderr/終了コードと未実行 lane を対応づける。失敗/timeout/対象外を別々に集計する。
4. 7子の完了と全 coverage を確認した後、[KUU-1480](https://linear.app/kuu/issue/KUU-1480) で原ケースの移設/削除・SKIP解除を行う。

この親作業では原ケースの `SKIP-DIFF` を維持する。
チケットに参照されている `docs/diff-skip-inventory.md` は確認対象 checkout に存在しないため、
手順の参照先には本書と契約監査を用いる。

## 親作業の確認範囲

保存 reference の整合性を以下で確認する。compiler 再実行は行わない。

```bash
python3 docs/fixtures/js_annotations/capture_reference.py \
  --check-record docs/fixtures/js_annotations/evidence/reference-results.json
python3 docs/fixtures/js_annotations/capture_reference.py \
  --expectations docs/fixtures/js_annotations/views-expectations.json \
  --check-record docs/fixtures/js_annotations/evidence/views-reference-results.json \
  --case views_map --case views_set --case views_readonly_array \
  --case views_dynamic --case views_variance
python3 Scripts/js_annotations/test_run_candidate.py
```

保存 reference の23ケースと view の5ケースは整合。
runner 回帰は11件成功。sandbox 内の初回は0.5秒の compile timeout 後の
`os.killpg` が拒否され、1件失敗したため、同じテストを sandbox 外で再確認した。
Markdown のローカルリンクと `git diff --check` も成功。
Swift source / runner / expectation / CI はこの親ブランチでは変更しない。
`swift build`、Swift tests、native fixture の再実行、全 Golden、全 diff、JS reference の再採取、
CI dispatch は未実行。
