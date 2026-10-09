# 3 collection view の検証 matrix (KUU-1614)

Kotlin 2.3.10 の [監査済み契約](../../../js-annotations-contract-2.3.10.md) に基づく。
期待値は `../views-expectations.json`、Kotlin/JS の実行記録は
`../evidence/views-reference-results.json` に source/compiler/stdlib の SHA と
compile/link/run の stdout・stderr・終了コード付きで保存する。

| 原ケースの観測 | fixture | 追加の観測 |
|---|---|---|
| Map の要素数 2 | `map.kt` の `minimum:2` | nullable key/value、generic Box、置換・削除・clear、順序、空 view の成長 |
| Set の要素数 3 | `set.kt` の `minimum:3` | nullable 要素、重複、追加・削除・clear、順序、空 view の成長 |
| readonly array の要素数 4 | `readonly_array.kt` の `minimum:4` | covariance、nullable 要素、置換・追加・削除・clear、順序、空 view の成長 |

各 view を変更前に取得し、同じ view を変更後に繰り返し観測する。
snapshot は変更前の内容を保持し、mutable conversion の変更は backing に反映しない。
コピーだけを返す view、初期 size を固定した view、conversion が backing を
返してしまう実装を検出する。`typed_views` の既存 generic/nullable fixture も実行する。

Kotlin の型付き公開面には、これら view の `size` / `length` / `set` / `add`
メンバーはない。`typed_view_properties` と `typed_mutators.kt` はその拒否を固定する。
view を Kotlin collection の typealias に置き換える実装もこの診断で検出する。
この subset の KSWIFTK-SEMA-0024 は DiagnosticRegistry の unresolved member call と
実際の8診断を確認して `UNRESOLVED_REFERENCE` に対応させる。
`variance.kt` は Map の key/value と Set の invariance、および readonly array の
逆方向代入を拒否する4診断を固定する。KSWIFTK-TYPE-0001 は generic な
type constraint failure なので、native 側では `TYPE_CONSTRAINT_FAILURE` に対応させ、
Kotlin/JS の `RETURN_TYPE_MISMATCH` 4件は別に保存する。
専用 `views-diagnostic-map.json` を使用し、共有 runner の分類には追加しない。

JS の動的 `set` / `add` / `delete` / `clear` と readonly index 書き込みは
`dynamic_views.kt` を実際の Kotlin/JS 2.3.10 で実行して確認する。
Map/Set の双方向共有と、readonly array の変更反映・書き込み拒否を含む。
これらは JS-only lane で、native candidate の成功件数に含めない。
native に存在しない変更 API を期待値のために追加しない。

## 実行

```bash
swift build
python3 Scripts/js_annotations/run_candidate.py \
  --expectations docs/fixtures/js_annotations/views-expectations.json \
  --diagnostic-map Scripts/js_annotations/views-diagnostic-map.json
```

7 native case の診断/実行結果を byte 比較し、JS-only case 1 件は out-of-lane と記録する。
初回 runtime ビルドは数分かかるため、先に compiler で最小ケースをリンクするか
`--compile-timeout 600` を指定する。実行自体の timeout は10秒のまま。
`--stdlib-library` で検証済み artifact を指定することもできる。
runner が返す artifacts パスに source、commands、toolchain identity、診断、
stdout/stderr/終了コード、summary.json が保存される。

Kotlin/JS reference の再採取:

```bash
python3 docs/fixtures/js_annotations/capture_reference.py \
  --expectations docs/fixtures/js_annotations/views-expectations.json \
  --kotlin-dir /path/to/kotlinc-2.3.10 --output-dir /tmp/js-views-reference \
  --case views_map --case views_set --case views_readonly_array --case views_dynamic --case views_variance
```

再採取は期待値を更新せず比較する。保存記録だけの整合性確認は
`--check-record docs/fixtures/js_annotations/evidence/views-reference-results.json`
を同じ5つの `--case` とともに指定する。

この PR のローカル検証は Linux x86_64 の新規 bundled `.kklib` と対象7ケース、
Kotlin/JS reference の runtime 4ケースと variance 診断1ケース。Runtime/RuntimeABI/Package.swift は基準 HEAD と同一で、
候補 compiler は別 worktree でビルドし、完成済み runtime cache は
`KSWIFTK_PACKAGE_ROOT` で検証済み元 checkout のものを使用した。
source injection / O2 の往復 matrix は KUU-1616、CI 接続は KUU-1617 が担当する。
全 Swift テスト・全 Golden・全 diff・JS emission/annotation/reflection は未実行。

既存 `collection_imports` fixture は未使用の未解決 import が受理される
[KUU-1736](https://linear.app/kuu/issue/KUU-1736) を検出する。
本 subset には含めず、元の oracle を保持する。全 import の検証修正は
lazy library materialization と bundled source の互換性を含めて別途扱う。
