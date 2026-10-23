# js_annotations の SKIP-DIFF 引継ぎ (KUU-1617)

本書は `Scripts/diff_cases/js_annotations.kt` の DEBT-DIFF-001 / KUU-1480 に限定する。
他の SKIP ケースの在庫数・完了状態を表さない。
`docs/diff-skip-inventory.md` は #8170 以降ローカル生成物として ignored のため、
共有する当該ケースの手順は本書に置く。
契約は [Kotlin 2.3.10 監査](js-annotations-contract-2.3.10.md)、期待値と provenance は
[fixture](fixtures/js_annotations/README.md) に置く。

## 移行先と実行 owner

移行先は **専用 candidate-only lane** とする。監査済み Kotlin fixture を
`docs/fixtures/js_annotations/` に保持し、`Scripts/js_annotations/run_ci.py` が
`run_matrix.py` 経由で全 native-compat fixture を選択する。
JVM 用の `diff_kotlinc.sh` に原ケースを再投入する方式は採らない。
古い原形は `diagnostics/original.kt` と reference evidence に保存済みである。
各専用 run は現在の diff case を `original-diff-case.kt` に保存し、
`inputs.json` に hash を記録する。歴史的原形と混同しない。

| 呼出し先 | 選択・実行範囲 | 証拠 |
|---|---|---|
| ローカル `python3 Scripts/js_annotations/run_ci.py --kswiftc <compiler>` | runner 回帰3本、native 27 fixture × source/artifact × O0/O2 (108 セル) | 一意の run directory の `evidence.md/json`、`matrix-results.json`、全 command/process/stdout/stderr |
| PR/merge queue: `ci.yml` → Repository checks | `test_run_candidate.py` / `test_run_matrix.py` / `test_summarize_evidence.py` | fake compiler による adapter と失敗検出の回帰。製品 matrix の PASS ではない |
| 日次/手動: `nightly-full.yml` → `verify-js-annotations` | 上記と同一の `run_ci.py`。当該 revision の release compiler から fresh `.kklib` を生成 | job summary と `js-annotations-evidence-<run id>` artifact。失敗時もアップロード |

Swift Testing の既存 annotation/metadata/view/reflection テストは日次の CompilerCore/Backend
shard が引き続き選択する。専用 runner の fixture 実行を、そのテストの成功で代替しない。
CI matrix は `continue-on-error` を使用しない。検証失敗・timeout・期待値欠落は job failure となる。
日次 matrix の失敗は最小 PR gate の成功とは別に扱う。

ローカルで全 matrix を回す compiler の準備は
`KSWIFTK_OPTIMIZE_COMPILER_CORE=1 swift build --product kswiftc` を推奨する。
CI の CompilerCore 最適化設定に合わせ、debug の Sema hot loop による過大な実行時間を避ける。
SwiftPM sandbox の制約がある場合は通常の権限あるターミナルで実行する。
製品が内部で起動する SwiftPM の sandbox 方針を変更する必要はない。

## 原ケースから coverage への対応

下表の fixture ID は全 matrix の必須入力に含まれる。各 ID の四経路の実測結果は
`evidence.md/json` に列挙され、未選択/未実行は `not-run` になる。
`pass` はその native 契約だけの成功であり、JS emission の成功を意味しない。

| 原形・現在の観測 | 移行先 fixture ID | 観測・判定 |
|---|---|---|
| `ExperimentalJsFileName("JsAnnotationsCase")` の古い FILE marker 用法 | `marker_as_file` | 引数/target 診断。古い全体は audit-only `original` |
| 現行 `@file:JsFileName("JsAnnotationsCase")` | `native_observations`, `file_name_no_opt_in`, `file_name_arguments`, `file_name_nonconstant`, `file_name_target` | file target、引数型、定数制約、受理、native stdout。JS ファイル名生成は reference consumer のみ |
| marker/opt-in の FQN と scope | `collection_marker_fqn`, `marker_no_opt_in`, `no_opt_in`, `marker_requirements` | 誤った FQN の拒否、warning の個数・severity、有効な opt-in scope |
| `asJsMapView` / `asJsSetView` / `asJsReadonlyArrayView` の不正な import | `collection_imports` | opaque view は member API。無効 import を個別診断 |
| `@ExperimentalJsExport class ExportedBox` | `marker_requirements`, `marker_no_opt_in`, `annotation_arguments`, `export_nonexportable`, `export_suspend` | marker と JsExport の別契約、引数、非 exportable type、suspend 診断 |
| object の `@ExperimentalJsStatic` / `JsHolder.message()` | `marker_requirements`, `static_accepted`, `static_receivers`, `static_visibility_const`, `native_observations` | marker-only と実 JsStatic を分離。通常呼出しの `js-annotations` を比較 |
| view の typed `.size` / `.length` | `typed_view_properties` | opaque 型の不正な property を拒否 |
| map/set/readonly array の `2:3:4` | `native_observations`, `typed_views`, `views_map`, `views_set`, `views_readonly_array` | 型付き conversion で count を観測。共有 backing、コピー、nullable generic、empty、clear/reuse を比較 |
| readonly/generic 型保持 | `views_typed_mutators`, `views_variance` | typed mutator 不在、Map/Set 不変・array 共変の診断 |
| 古い裸の `(::createInstance).name` | `bare_create_instance` | receiver 不在の参照を拒否 |
| bound/unbound `createInstance` の参照名 | `native_observations`, `unbound_create_instance` | `createInstance` と receiver/戻り値 generic metadata を実行比較 |
| `ExportedBox::class.createInstance().value == 7` | `native_observations`, `reflection` | default constructor、既定値の毎回評価、候補0/複数の失敗 |
| `ExportedBox:createInstance:7` 全体 | `native_observations` | stdout `js-annotations\n2:3:4\nExportedBox:createInstance:7\n` の byte 比較 |
| JS export/file/static の実 emission、dynamic view | `native_observations.consumer`, `marker_requirements.consumer`, `js_dynamic_views`, `views_dynamic` | 保存済み Kotlin/JS 2.3.10 oracle。native lane 対象外であり KSwiftK PASS に数えない |

27 native fixture 全体を固定するため、原形に直接現れない negative/metadata fixture も外さない。
`original`, `js_dynamic_views`, `views_dynamic` は native 対象外として明示する。

## 証拠と未達項目

KUU-1616 の過去の保存記録 `fixtures/js_annotations/evidence/native-matrix-results.json` は
**56 pass / 52 fail / 0 timeout / 0 not-run**。全27 fixture は四経路で同じ結果だったが、
13 fixture の native 契約検証が成功していない。
adapter 未対応による失敗と製品の契約不一致を、同じ「未実装」と判断しない。別の focused 記録の12/12成功で、
全体の52失敗を上書きしない。

失敗には未接続の診断 adapter、診断個数の不一致、`collection_marker_fqn` の誤受理が含まれる。
`evidence.md` は各 fixture の理由を列挙する。adapter の対応づけは実際の診断意味を根拠に行い、
期待値の削減や warning 無視で PASS にしない。
たとえば `KSWIFTK-SEMA-0024` は `ScopeBuilder` の無効 import と未解決 member の
双方で使用される。現在の view map は `UNRESOLVED_REFERENCE` に対応づけるため、
`collection_imports` の `UNRESOLVED_IMPORT` は番号だけの一括変換では一致しない。
診断の message/range と fixture 文脈を確認する adapter が必要となる。製品の修正・契約の改訂は担当チケットと照合する。
番号の対応づけだけでは解消しない観測も、保存記録にある:

| fixture | native 契約 | 保存記録の実測 | 必要な確認 |
|---|---|---|---|
| `bare_create_instance` | UNRESOLVED_REFERENCE の error 2件 | SEMA-0022 の error 1件 | `.name` を含む診断回復の契約と個数を照合 |
| `marker_no_opt_in` | OPT_IN_USAGE の warning 3件 | 同 warning 2件 | marker requirement の伝播・利用地点を照合 |
| `collection_marker_fqn` | compile exit1、定数/参照 error 2件 | compile exit0、診断0件 | 無効 FQN の受理を照合 |

これらは上記の過去 matrix で観測された不一致であり、その時点では KUU-1480 の SKIP 解除は
**needs attention** だった。

2026-10-13 JST の最初のローカル実行は Runtime の packaged SwiftPM build が
`sandbox_apply: Operation not permitted` となったため中断した。stdlib artifact の生成は
成功し、4セルが失敗、残り104セルは未実行だった。この中断記録は完全 matrix の証拠ではなく、製品だけの失敗数にも混ぜない。
実行環境を変更した再検証では Runtime の sandbox 障害は解消したが、
高負荷の下で debug CompilerCore の Sema に時間がかかり、source/O2 の
`marker_requirements` と `native_observations` が compile timeout (600秒) となった。
45セルの結果は 17 pass / 26 fail / 2 timeout、残り63セルは未実行で、同じソースから `KSWIFTK_OPTIMIZE_COMPILER_CORE=1` で compiler を再ビルドした。
stack sample は LLVM 前の `collectOperatorCandidates` / `StringInterner.resolve` を示した。
この中断記録も完全 matrix ではない。再検証は別 run directory / fresh artifact を使用し、
compiler SHA を区別する。

同日の最適化 compiler による再実行は **56 pass / 52 fail / 0 timeout / 0 not-run**、
27 fixture の経路間不一致0で完了した。全四経路それぞれ14 pass / 13 failで、
KUU-1616 の保存結果と同じ分類だった。runner 回帰は11 + 6 + 8 = 25件すべて成功、
fresh stdlib build は exit0 / 74.48秒、専用コマンド全体は契約不一致により exit1。
旧実行の Runtime sandbox 障害と二つの compile timeout はこの再実行では発生していない。

| 保存ファイル | 内容 |
|---|---|
| [kuu-1617-native-matrix-results.json](fixtures/js_annotations/evidence/kuu-1617-native-matrix-results.json) | 全108セルの portable matrix、全artifactファイルのhash、toolchain、期待値/map hash、経路間比較 |
| [kuu-1617-ci-results.md](fixtures/js_annotations/evidence/kuu-1617-ci-results.md) | 解除判定false、fixture別結果・理由、runner回帰、実際のbuild/検証コマンド、CI未実行 |

実行は2026-10-13 10:13:25–10:35:41 JST、revision
`4838c0b14c1d4a3cb279a198a721bf8d1cac2f6f`、Apple Swift 6.4 / arm64 macOSで行った。
compiler SHA256 は `587ddd6eb8cc0e53cf1143b043dd2ed63c0f232a20b99621dce838a6cf27e7da`、
fresh artifact は `c0cd074e28118007fde9ca65af1b6d3b8305350c06b60c7c46d1f7aae1638e79`、
manifest は `f9c359a32e34d9bbf5b8ea627d5de3bcbb718c8c7622c9a777ecb4f1c1242369`。
ローカルはdebug CLI + 最適化 CompilerCore、CIはSwift 6.3 / Linux release compilerであり、
ローカル結果をCI上の実測と同一視しない。

ローカル再実行の結果は `run_ci.py` の一意の directory へ保存する。toolchain/version、revision、
compiler/source/artifact/manifest hash、期待値/map hash は `matrix-results.json`、正確な command、
compile と run の stdout/stderr/終了コード/timeout は matrix directory の各 process 記録にある。
過去の記録の集約だけを現在の compiler の再実行と呼ばない。

2026-10-15 JST の統合後ローカル candidate-only 実行は `run_ci.py` の exit 0 で完了し、
runner 回帰3本と native 27 fixture × source/artifact × O0/O2 の108セルがすべて PASS、
fail / timeout / not-run は0、経路間不一致は0、`skipRemovalReady` は `true` だった。
`KOTLINC=/__codex_missing_kotlinc JAVA_BIN=/__codex_missing_java` を指定しており、
JVM reference は実行経路にない。run directory は
`.artifacts/js_annotations_ci/20261014T191310.036137Z-b64c599e/`、matrix は
`matrix/20261014T191321.536958Z-b13578d1/`。
revision は `3c22b11e547b755dda56dd05e921e17bd8056084`、CompilerCore source tree hash は
`5ac1f34132d6894abfbd7e58969cce62940c1e8f0e58352af5b54d4efd5ff427`、compiler SHA256 は
`a0d9cac1239aa2ed6ab29c2ae3f57931ccbc9a02d6837b8243dccbcb97eed867`。
fresh 1849-file artifact SHA256 は `cfdfd80867af93a15754f15ff30f2d563bbd605857b763169f7804d7096860b7`、
manifest SHA256 は `4968c760ccd9d5699772443be1a8b1a4cda0d995b9b69d856d992167c8efda3d`。
実行環境は macOS 27 / Apple Swift 6.4 arm64。
このrevisionには #9027 / #9041 の変更を積んでいる。当時 #9038 は merge queue 待ちのため含めず、
同PRが扱う unchecked cast warning は、このローカル実行では redundant cast の除去で回避している。
#9038 はその後 2026-10-15 JST に merge された。

2026-10-15 JST に同 revision `34858c2b01701c2f3caf8d12056779131de0c802` の hosted job を実行した。
[workflow run 38624667409](https://github.com/kuu-lab/swifty-kotlin/actions/runs/38624667409) の
[専用 job](https://github.com/kuu-lab/swifty-kotlin/actions/runs/38624667409/job/116067141702)
は成功し、summary は `status=pass`, `case-runs=108`, `failed=0`, `inconsistent=0`, `excluded=3`。
pass 108、fail / timeout / not-run はすべて0で、`SKIP removal ready: true`。
source/artifact × O0/O2 の全27 native fixture が一致し、runner 回帰の
`test_run_candidate`, `test_run_matrix`, `test_summarize_evidence` も exit 0 だった。
除外された `original`, `js_dynamic_views`, `views_dynamic` は native lane 対象外として記録されている。
matrix run ID は `20261014T195255.092494Z-1e003c9e`、hosted release compiler は Apple Swift 6.3.3。
`KOTLINC` と `JAVA_BIN` はどちらも `/not-used-by-js-annotations` に設定され、JVM reference は起動していない。

evidence artifact は [js-annotations-evidence-38624667409 (ID 11927057209)](https://github.com/kuu-lab/swifty-kotlin/actions/runs/38624667409/artifacts/11927057209)。
upload SHA-256 は `f80c2901f652069c875aac97256cff064c38ed8c886cf479f76a110caa65d004`、
size は 788982642 bytes。release compiler artifact `kswiftc-release-38624667409` は
SHA-256 `0258ecc706cffebc9bc98cf63ff10e8c52926f0c3fe073fe1a4e47537487d6f1` を検証してから実行した。
この hosted run では別 job `Build debug Swift test bundle once` の一般 candidate-only diff 検証が10件失敗し、
通常の kotlinc diff shard job も失敗したため、nightly workflow 全体を green とは扱わない。
専用 JS annotation job の成功はそれらの結果と分けて記録する。

### 移設後の hosted 再実行

`Scripts/diff_cases/js_annotations.kt` を audit snapshot へ移して削除した revision
`a9b9bbda0b8dc7d2f2e8f2a7d7382b84f58cfe2b` でも、2026-10-15 JST に同じ専用 job を再実行した。
[workflow run 38635184807](https://github.com/kuu-lab/swifty-kotlin/actions/runs/38635184807) の
[専用 job](https://github.com/kuu-lab/swifty-kotlin/actions/runs/38635184807/job/116101899388)
は成功し、summary は `status=pass`, `case-runs=108`, `failed=0`, `inconsistent=0`, `excluded=3`。
pass 108、fail / timeout / not-run はすべて0、`SKIP removal ready: true`。
runner 回帰3本もすべて exit 0。matrix run ID は `20261014T210139.885569Z-502d3953`、
evidence directory は `20261014T210131.230155Z-65dcbfc4`。
JVM reference を起動しないよう `KOTLINC` / `JAVA_BIN` は未存在の指定先に固定した。

移設後 evidence artifact は
[js-annotations-evidence-38635184807 (ID 11929923733)](https://github.com/kuu-lab/swifty-kotlin/actions/runs/38635184807/artifacts/11929923733)。
upload SHA-256 は `e756996e35109235e304ade0d3cba02b994f1c92e719957524dffa7a9baae7c0`、
size は 788982207 bytes。この run も一般 candidate-only diff verification と kotlinc diff shard が失敗し、
nightly workflow 全体は failure。専用 JS annotation job の pass および PR の必須 checks pass とは区別する。

集約器は compile/runtime timeout を `timeout`、artifact build 失敗によって開始できなかった
fixture を `not-run`、実行した契約不一致を `fail` とする。artifact build 自身の timeout は
上位の `failureReasons` と stdlib-build process 記録に残す。期待した compile failure の後の
runtime は `not_applicable` であり、未実行の肯定 runtime を PASS にするものではない。

KSwiftK JS emission/consumer、全 Swift suite、全 diff corpus はこの専用 job では未実行。
run URL、summary、evidence artifact は上記 hosted job の記録を参照する。

## KUU-1480 が実行する解除手順

1. 同一 revision の compiler をビルドして `run_ci.py` を全ケースで実行する。既存 `.kklib` を
   渡さず、fresh artifact と source × O0/O2 の全108セルを得る。
2. 全108セルとrunner回帰3本の成功、artifact identity、全 coverage 行を確認する。
   `evidence.json` の `skipRemovalReady: true` が必要。失敗/timeout/not-run が残れば解除しない。
3. ブランチ上で `nightly-full.yml` の専用 job を実行し、run URL、summary、artifact を保存する。
   ローカル成功だけで「CI 実行済み」としない。
4. 解除時点の `Scripts/diff_cases/js_annotations.kt` を独立した audit snapshot として
   [`fixtures/js_annotations/evidence/kuu-1480-diff-case-before-removal.kt`](fixtures/js_annotations/evidence/kuu-1480-diff-case-before-removal.kt)
   に保存する。45行、SHA-256 `c0907499c4fb7b25f062cf84e9763e673621a7ae8c0a1243a1cbc783713c4a03`。
   歴史的 `diagnostics/original.kt` は上書きしない。
5. native 肯定観測の owner を `valid/native_observations.kt` と専用 lane に確定し、
   無効 FQN/import/property/reference の各診断を対応表で確認する。JS emission の達成を主張しない。
6. KUU-1480 の独立 PR で diff case を専用 fixture lane に移設し、旧 diff file を削除する。
   これにより当該 SKIP-DIFF も削除される。タグだけを外して JVM diff に戻さない。
7. fixture、期待値、必須 sentinel、CI 選択が残っていることを再確認し、移設後にも専用 job を実行する。
   実行結果は上記 `移設後の hosted 再実行` に保存した。

KUU-1617 の時点では接続・証拠集約のみを変更し、原 diff case と SKIP-DIFF を保持していた。
KUU-1480 で上記の native-only lane へ移設した。
