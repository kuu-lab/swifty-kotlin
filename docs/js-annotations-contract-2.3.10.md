# js_annotations: Kotlin 2.3.10 契約監査 (KUU-1604)

監査日: 2026-10-08 JST。対象は `Scripts/diff_cases/js_annotations.kt`。
成果物は本書と [`fixtures/js_annotations/`](fixtures/js_annotations/)。
製品実装は [KUU-1605〜1611](https://linear.app/kuu/issue/KUU-1602)、
candidate-only runner は [KUU-1612](https://linear.app/kuu/issue/KUU-1612) が担当する。
元ケースの振り分け・移設・削除・SKIP 解除は [KUU-1480](https://linear.app/kuu/issue/KUU-1480) の担当である。

## 1. Oracle と監査範囲

基準は **Kotlin/JS 2.3.10**。JVM kotlinc の受理/拒否や現在の KSwiftK の
`KSWIFTK-SEMA-0024` / `0022` は、この入力の Kotlin/JS 上の有効性を証明しない。
タグ `v2.3.10` の commit は `679366a83f99851b42f64795f10ed803ff011c73`。
最新版の API サイトをバージョン固定の証拠として使わない。

次の公式ソースと、同バージョンの compiler / stdlib を照合した。

| 根拠 | 監査する内容 |
|---|---|
| [common/JsAnnotationsH.kt](https://github.com/JetBrains/kotlin/blob/v2.3.10/libraries/stdlib/common/src/kotlin/JsAnnotationsH.kt) | marker、expect annotation、target、retention、opt-in |
| [JS/annotationsJs.kt](https://github.com/JetBrains/kotlin/blob/v2.3.10/libraries/stdlib/js/src/kotlin/annotationsJs.kt) | JS actual annotation |
| [JS/builtins/Collections.kt](https://github.com/JetBrains/kotlin/blob/v2.3.10/libraries/stdlib/js/builtins/Collections.kt) | 3 view メンバーの所有型・戻り値・requirement |
| [JS/js.collections.kt](https://github.com/JetBrains/kotlin/blob/v2.3.10/libraries/stdlib/js/src/kotlin/js.collections.kt) | opaque external 型と公開 conversion |
| [JS/runtime/collectionsInterop.kt](https://github.com/JetBrains/kotlin/blob/v2.3.10/libraries/stdlib/js/runtime/collectionsInterop.kt) | shared backing、conversion のコピー、JS 操作 |
| [JS/reflect/createInstance.kt](https://github.com/JetBrains/kotlin/blob/v2.3.10/libraries/stdlib/js/src/kotlin/reflect/createInstance.kt) | constructor 呼出しと失敗経路 |
| [FirJsStaticChecker.kt](https://github.com/JetBrains/kotlin/blob/v2.3.10/compiler/fir/checkers/checkers.js/src/org/jetbrains/kotlin/fir/analysis/js/checkers/declaration/FirJsStaticChecker.kt) | receiver、visibility、const 制約 |
| [FirJsExportDeclarationChecker.kt](https://github.com/JetBrains/kotlin/blob/v2.3.10/compiler/fir/checkers/checkers.js/src/org/jetbrains/kotlin/fir/analysis/js/checkers/declaration/FirJsExportDeclarationChecker.kt) | export 宣言/公開型の診断 |

compiler archive は既存 CI と同じ SHA-256
`c8d546f9ff433b529fb0ad43feceb39831040cae2ca8d17e7df46364368c9a9e`
を `Scripts/verify_kotlin_compiler_archive.sh` で照合して専用一時ディレクトリへ展開した。
実行環境・artifact hash・各 fixture の hash・コマンド・診断・stdout/stderr・終了コードは
[`evidence/reference-results.json`](fixtures/js_annotations/evidence/reference-results.json) に保存する。

## 2. Annotation と marker

この表の短縮名の FQN prefix は全て **`kotlin.js.`**。
引数「なし」は引数ゼロの annotation constructor を表す。

| 短縮名 | 引数 | target | retention | requirement / 意味 |
|---|---|---|---|---|
| `ExperimentalJsFileName` | なし | 明示 `@Target` なし、宣言用の既定 target。FILE 不可 | BINARY | WARNING の opt-in marker。file name 自体を指定しない |
| `JsFileName` | `name: String`、既定値なし、定数 | FILE | SOURCE | common expect は `ExperimentalJsFileName`。JS actual は marker なし。JS per-file 出力名を指定 |
| `ExperimentalJsExport` | なし | 明示 `@Target` なし、宣言用の既定 target。FILE 不可 | BINARY | WARNING の opt-in marker。export 自体を行わない |
| `JsExport` | なし | CLASS, PROPERTY, FUNCTION, FILE | BINARY | `ExperimentalJsExport`。JS export を指定 |
| `ExperimentalJsStatic` | なし | 明示 `@Target` なし、宣言用の既定 target。FILE 不可 | BINARY | WARNING の opt-in marker。static method 自体を生成しない |
| `JsStatic` | なし | FUNCTION, PROPERTY, PROPERTY_GETTER, PROPERTY_SETTER | BINARY | `ExperimentalJsStatic`。companion member の追加 static entry を指定 |
| `ExperimentalJsCollectionsApi` | なし | CLASS, FUNCTION | BINARY | WARNING の opt-in marker。`kotlin.js.collections` 配下には存在しない |
| `ExperimentalJsReflectionCreateInstance` | なし | CLASS, ANNOTATION_CLASS, PROPERTY, FIELD, LOCAL_VARIABLE, VALUE_PARAMETER, CONSTRUCTOR, FUNCTION, PROPERTY_GETTER, PROPERTY_SETTER, TYPEALIAS | BINARY | WARNING の opt-in marker |

明示 target のない3 marker は既定の宣言 target のため FILE 不可。
`ExperimentalJsFileName` の file 適用は fixture でも拒否を確認した。
適用可能な既定 target は原形の診断に保存されている。`@file:OptIn(Marker::class)` の
FILE は **OptIn の target** であり、marker 自体の FILE target とは異なる。

`@OptIn(Marker::class)` と `-opt-in=<FQN>` は使用側の requirement を満たす。
宣言に直接 `@ExperimentalJsExport` / `@ExperimentalJsStatic` を付けると、
その宣言の利用側へ requirement が伝播する。実 annotation の代用品にはならない。
`marker_requirements.kt` は使用側も opt-in して受理される例、
`marker_no_opt_in.kt` は利用側の warning を残す例である。

opt-in 不足の既定 severity は **warning**。本監査では diagnostic fixture の
コンパイルに `-Werror` を付けず、受理された warning と compile error を区別する。
有効 fixture には `-Werror` を付け、必要な requirement を満たしたことを確認する。

### 実 annotation の意味と制約

- `JsFileName`: 元の `ExperimentalJsFileName("JsAnnotationsCase")` は
  FILE target と引数数の両方が不正。有効形は
  `@file:kotlin.js.JsFileName("JsAnnotationsCase")`。
  common expect は marker requirement を宣言するが、JS actual には marker がなく、
  **2.3.10 JS の利用は opt-in なしでも warning なし**。
  `file_name_no_opt_in.kt` でこの差を固定する。
  統合 fixture は common 側の意図も明示するため opt-in を記述している。
  出力名の効果は `-Xir-per-file` の JS 出力を実際に生成して観測する。
- `JsExport`: 本 fixture の top-level `ExportedBox(val value: Int = 7)` は有効。
  `Int` の property/default argument と constructor は JS consumer からも観測する。
  `suspend` の export は通常設定で `WRONG_EXPORTED_DECLARATION`。
  未 export の `InternalBox` を返す `export_nonexportable.kt` は
  `NON_EXPORTABLE_TYPE` **warning** でコンパイル終了コード0。
  export 公開型の制約は severity も含めて扱い、
  source comment の禁止事項一覧だけを機械的に実装仕様へ転記しない。
  nested `JsExport.Ignore` / `Default` は原ケースに使われていないため今回の実装範囲外。
- `JsStatic`: class / interface の public companion member は有効。
  interface companion は 2.3 から既定で有効になった `JsStaticInInterface` による。
  通常の object 内の member と
  class の instance member は `JS_STATIC_NOT_IN_CLASS_COMPANION`。
  非 public member（property の private setter を含む）は `JS_STATIC_ON_NON_PUBLIC_MEMBER`、
  `const` property は `JS_STATIC_ON_CONST`。
  **トップレベルの適用は 2.3.10 に受理される**。FIR checker が enclosing class のない
  宣言を検査対象から返すためで、追加 class static entry の効果を保証しない。
  export のない class / interface の companion も受理される。JS consumer に公開する fixture では
  enclosing class を `JsExport` し、その class の static call を検証する。

SOURCE retention を BINARY/RUNTIME に改変しない。annotation 定義の属性と、
後段の出力生成用に必要な compile-time 情報を区別する。
`.kklib` 往復は definition / requirement / compilation metadata の契約を検査し、
SOURCE usage を公開 binary/runtime annotation record として保存・再露出しない。
中間 IR が後段出力に渡す compiler-owned 情報とは別の保持規則であり、
SOURCE annotation を runtime reflection から読める契約にはしない。

## 3. Collection の宣言と公開面

以下は `kotlin.collections` の **メンバー** である。
`kotlin.js.collections.asJsMapView` などのトップレベル extension は存在しない。
引数は全てゼロ。3メンバーとも `ExperimentalJsExport` と
`ExperimentalJsCollectionsApi` の両方を要求する。

| 所有型（receiver）/メンバー | 戻り型の FQN | 型保持 |
|---|---|---|
| `MutableMap<K, V>.asJsMapView` | `kotlin.js.collections.JsMap<K, V>` | K/V invariant、nullable も保持 |
| `MutableSet<E>.asJsSetView` | `kotlin.js.collections.JsSet<E>` | E invariant、nullable も保持 |
| `List<out E>.asJsReadonlyArrayView` | `kotlin.js.collections.JsReadonlyArray<E>` | 戻り型も `out E` |

`JsMap<K, V>` は external open class で `JsReadonlyMap<K, out V>` を実装、
`JsSet<E>` は external open class で `JsReadonlySet<out E>` を実装する。
`JsReadonlyArray<out E>` は external interface。
これらの公開 Kotlin 宣言には **size / length / get / set / add / delete のメンバーがない**。
native 実装で `MutableMap` / `MutableSet` / `List` へ typealias すると、upstream が拒否する
`.size` を誤って受理するため不可。

`kotlin.js.collections` に実在する、今回必要な公開 extension は次の6つ。
全て inline、引数ゼロ、`ExperimentalJsCollectionsApi` requirement を持つ。

| receiver | extension 名 → 戻り型 | 操作 |
|---|---|---|
| `JsReadonlyMap<K, V>` | `toMap` → `Map<K, V>`、`toMutableMap` → `MutableMap<K, V>` | 内容のコピー |
| `JsReadonlySet<E>` | `toSet` → `Set<E>`、`toMutableSet` → `MutableSet<E>` | 内容のコピー |
| `JsReadonlyArray<E>` | `toList` → `List<E>`、`toMutableList` → `MutableList<E>` | 内容のコピー |

型付きの要素数観測は `map.asJsMapView().toMap().size`、
`set.asJsSetView().toSet().size`、`list.asJsReadonlyArrayView().toList().size` とする。
コピー取得後に backing を変更してもコピーは変わらない。
**view 自体は backing を共有する** ので、同じ view をもう一度変換した結果には変更が反映される。
conversion の mutable 結果を変更しても backing へ逆反映しない。
`typed_views.kt` は generic/nullable、array covariance、空入力、変更反映とコピー独立性を観測する。

### JS の公開操作と native の境界

JS consumer または Kotlin/JS の `asDynamic()` からは次を観測できる。
native 側へ dynamic や任意 JS object を追加する根拠にはしない。

| view | JS 上の操作 | 観測/注意 |
|---|---|---|
| Map | `size`, `get`, `set`, `has`, `delete`, `clear`, `keys`, `values`, `entries`, `forEach`, `Symbol.iterator` | backing と双方向共有。`set` は view 自身を返す |
| Set | `size`, `add`, `has`, `delete`, `clear`, `keys`, `values`, `entries`, `forEach`, `Symbol.iterator` | backing と双方向共有。`add` は view 自身、`delete` は Boolean |
| Readonly array | `length`、index 読出し、array の読取操作 | backing list の構造変更も反映。`.size` は JS 上でも `undefined`。要素書込は `UnsupportedOperationException` |

Map の `delete` は 2.3.10 の wrapper 内で `mapRemove: (K) -> Unit` に接続されている。
一般の JavaScript Map の Boolean 返値を無条件に oracle にせず、今回の実行結果の
Kotlin Unit object（JS の `typeof` は `object`）を保存する。
array Proxy の length 書込など、未観測の例外詳細まで
要素書込の結果から一般化しない。iterator / callback / 任意 JS value の ABI は JS 専用契約。

## 4. createInstance と callable reference

FQN は **`kotlin.reflect.createInstance`**。
receiver は `KClass<T>`、型パラメータ制約は `T : Any`、引数ゼロ、戻り型は `T`。
requirement は `kotlin.js.ExperimentalJsReflectionCreateInstance`。
`kotlin.reflect.full.createInstance` は別 API で、この FQN を置換しない。

原形の `(::createInstance).name` は receiver のない名前解決になり、
2.3.10 は `createInstance` と続く `name` を `UNRESOLVED_REFERENCE` として拒否する。
有効形は `(ExportedBox::class)::createInstance`、または
`KClass<ExportedBox>::createInstance`。前者は receiver を束縛した引数ゼロの参照、
後者は呼出し時に `KClass<ExportedBox>` を渡す参照である。
`.name` の期待値は `createInstance`。

`ExportedBox(val value: Int = 7)` の direct call と bound reference call は value=7 を返す。
`reflection.kt` は既定値評価が各生成で行われること、引数ゼロ constructor、
必須引数だけを持つ constructor の `IllegalArgumentException` を観測する。
JS 本体は constructor metadata の `defaultConstructor` を使う。
複数 constructor、可視性、全種類の失敗 matrix は KUU-1611 / 1615 の追加回帰範囲であり、
本書は未採取の診断/例外を採取済みとして扱わない。

## 5. Native 互換契約と JS emission

この表は **後続実装が満たす契約** で、現行 KSwiftK の実装済み一覧ではない。
[stdlib-pipeline §9](stdlib-pipeline.md#9-合成スタブ-3-分類棚卸し-rf-stub-001) と
[DEBT-DIFF-001](diff-skip-inventory.md#debt-diff-001-reference-target--classpath--runtime-only) の
JS/Wasm target-out 方針を維持する。対象 issue が要求する限定的な native source
compatibility を、JS backend/外部 object ABI のサポートへ拡大しない。

| 対象 | native に提供する互換動作 | JS の別観測/未実装機能 |
|---|---|---|
| marker / OptIn | 正しい FQN、target、引数、WARNING requirement、伝播と definition metadata | marker 単体には export/file/static emission はない |
| JsFileName | JS actual に合わせた引数/target/retention/compile-time 情報。marker 使用側の opt-in は扱うが、JsFileName 自体に JS actual にない warning を課さない | `JsAnnotationsCase.mjs` の生成は JS per-file emitter が必要。native executable の名前変更を同等としない |
| JsExport | 宣言/公開型検査、opt-in、export intent metadata、通常の Kotlin constructor/property | JS module export と unmangled JS entry / d.ts は未実装、target-out |
| JsStatic | receiver/visibility/const 検査、opt-in、member intent metadata、Kotlin companion call | JS class の追加 static function/getter/setter は未実装、target-out |
| Map view | opaque typed wrapper に backing を保持し、`toMap` / `toMutableMap` をコピーとして提供 | JS Map-like object、dynamic mutation/iteration/callback は target-out |
| Set view | opaque typed wrapper と shared backing、`toSet` / `toMutableSet` のコピー | JS Set-like object、dynamic mutation/iteration/callback は target-out |
| Readonly array view | covariance を保持した opaque wrapper、`toList` / `toMutableList` のコピー、backing 変更反映 | JS Proxy/Array ABI、dynamic index/length 操作は target-out |
| createInstance | 正しい JS API FQN/marker/receiver/generic を既存 constructor machinery に接続、既定値/失敗/参照名 | JS constructor metadata/JS allocation ABI を native Runtime と同一扱いしない |

native wrapper は JS external 型の実体ではなく、KSwiftK の互換実装として記録する。
JS runtime / dynamic 用の宣言を既定 stdlib に一括で再導入しない。
後続はこの差を実装ファイル/台帳へ残し、source injection と新しい `.kklib` の往復、
O0/O2 で個々の native 観測を検証する。
annotation の受理や Kotlin stdout の一致だけで JS emission の完全実装を報告しない。
KUU-1602 の完了報告も native 互換の達成範囲と JS target-out の残件を併記する。

## 6. 元ケースから fixture への対応

| 原形/観測 | 結論・変更理由 | 保存先 |
|---|---|---|
| 元ファイル全体 | 有効入力ではない。byte-identical snapshot と全診断を保存 | `diagnostics/original.kt` |
| `@file:ExperimentalJsFileName("JsAnnotationsCase")` | 引数ゼロ marker は FILE 不可。実 `JsFileName` と opt-in を使う | `diagnostics/marker_as_file.kt` / `valid/native_observations.kt` |
| `kotlin.js.collections.ExperimentalJsCollectionsApi` | FQN は `kotlin.js.ExperimentalJsCollectionsApi` | `diagnostics/collection_marker_fqn.kt` / 有効 view fixtures |
| 3 `asJs*View` import | extension ではなくメンバーなので import を削除 | `diagnostics/collection_imports.kt` |
| `@ExperimentalJsExport class ExportedBox` | marker 用法自体は有効、利用側に opt-in が必要。JS export には JsExport | `valid/marker_requirements.kt` / `diagnostics/marker_no_opt_in.kt` / `valid/native_observations.kt` |
| object 内の `@ExperimentalJsStatic` | marker 用法自体は有効。実 JsStatic にする場合は public companion へ | marker fixtures / `diagnostics/static_receivers.kt` / `valid/native_observations.kt` |
| `JsHolder.message()` → `js-annotations` | companion の通常呼出しを保持。JS static の呼出しは別 consumer | `valid/native_observations.kt` / `valid/js_emission.mjs` |
| 3 view の `.size` → `2:3:4` | opaque 型には property 不在。型付き conversion 経由で観測 | `diagnostics/typed_view_properties.kt` / `valid/native_observations.kt` |
| JS object の要素数 → `2:3:4` | JS Map/Set は size、array は length。native typed 観測とは別 | `valid/js_dynamic_views.kt` |
| `(::createInstance).name` | receiver 不在で無効。bound / typed unbound reference へ | `diagnostics/bare_create_instance.kt` / `valid/reflection.kt` |
| `ExportedBox::class.createInstance()` → value=7 | direct call と default constructor の観測を保持 | `valid/native_observations.kt` / `valid/reflection.kt` |
| `ExportedBox:createInstance:7` | simpleName、正しい参照の name、生成 instance を統合して観測 | `valid/native_observations.kt` |
| JS export / file / static effect | 元ケースの stdout だけでは検証されていない。module の実 import で追加観測 | `valid/js_emission.mjs` と per-file artifact の相対名 |

## 7. 期待値形式と runner への引継ぎ

[`expectations.json`](fixtures/js_annotations/expectations.json) の `schemaVersion: 1` を使用する。
case ごとに source path/hash、lane、compile 終了コード/diagnostics、run の
stdout/stderr/終了コードと provenance を必須とする。
成功する compile の diagnostic は空配列、warning fixture は severity 付きの非空配列。
compile-failure fixture に run を実行しない。

reference の診断は `-Xrender-internal-diagnostic-names` の ID と severity の multiset を比較する。
native 診断は同じ意味の `contractDiagnostics` と照合する adapter を KUU-1612/1613 で作る。
upstream ID を KSWIFTK の数字コードだと仮定しない。adapter の未定義 code は失敗にする。
原形全体は複合エラーの監査資料であり、native 診断の完全一致は要求せず、
分離した fixture の意味単位を検証する。

run の stdout/stderr は UTF-8、LF、末尾 newline を含めて完全一致させる。
trim、行の sort、stderr と stdout の混合、例外メッセージの黙った置換をしない。
compiler の進捗/時間ログは raw evidence へ保存し、runtime stderr と別に扱う。
compile / JS link / run の timeout は各々失敗とする。signal 終了、期待値/hash 不足、
unknown lane、出力不一致、compile 成功後の artifact 不在も成功/skip に変えない。
native runner は **JVM reference を起動しない**。reference の再採取は独立した監査用コマンドである。

native lane は `native_observations`, `marker_requirements`, `typed_views`, `reflection`,
`static_accepted`, `file_name_no_opt_in` と native に対応する診断 fixture。
`js_dynamic_views` と `js_emission` は JS 専用 lane で、native PASS 件数へ算入しない。
file naming の証拠は source-to-module 相対名、export/static の証拠は consumer assertions。
最適化/source injection/artifact の結果は期待値を流用しても、別 lane の実行記録にする。

## 8. 7実装チケットの所有範囲

| owner | 確定した範囲 | 依存/境界 |
|---|---|---|
| [KUU-1605](https://linear.app/kuu/issue/KUU-1605) | JsFileName / ExperimentalJsFileName の定義、file scope、引数/target/opt-in、retention と compilation metadata | JS 出力名の生成は native 受理とは別。元 marker の negative を維持 |
| [KUU-1606](https://linear.app/kuu/issue/KUU-1606) | JsExport / ExperimentalJsExport、宣言/型制約、requirement と export intent metadata | view 3メンバーの ExperimentalJsExport を所有。JS module emission を完了扱いしない |
| [KUU-1607](https://linear.app/kuu/issue/KUU-1607) | JsStatic / ExperimentalJsStatic、class/interface の public companion/通常 object/instance/top-level、visibility/const、requirement と member metadata | marker と実 annotation を分離。追加 JS entry は別 capability |
| [KUU-1608](https://linear.app/kuu/issue/KUU-1608) | MutableMap メンバー、JsMap/JsReadonlyMap の opaque 型、2 map conversion、shared backing とコピー、ExperimentalJsCollectionsApi と最小共通基盤 | 1606 に依存。JsMap.size 等の架空 Kotlin API を追加しない。Set/array はこの基盤を再利用 |
| [KUU-1609](https://linear.app/kuu/issue/KUU-1609) | MutableSet メンバー、JsSet/JsReadonlySet、2 set conversion、型/nullable/重複/shared backing とコピー | marker/共通基盤は1608。JS逆変更の証拠を native conversion の変更で代用しない |
| [KUU-1610](https://linear.app/kuu/issue/KUU-1610) | List メンバー、JsReadonlyArray covariance、2 list conversion、順序/空/shared backing/コピーと readonly 公開面 | marker/共通基盤は1608。JsArray や dynamic runtime を範囲へ吸収しない |
| [KUU-1611](https://linear.app/kuu/issue/KUU-1611) | kotlin.reflect.createInstance / ExperimentalJsReflectionCreateInstance、receiver/generic/opt-in、default constructor、bound/unbound reference/name、失敗経路 | 共通 constructor 処理は [KUU-1377](https://linear.app/kuu/issue/KUU-1377)、metadata/callBy は [KUU-1446](https://linear.app/kuu/issue/KUU-1446)。別 FQN の実装を吸収しない |

独立検証の annotation matrix は KUU-1613、view matrix は KUU-1614、reflection は KUU-1615、
source injection / `.kklib` × O0/O2 は KUU-1616、CI/SKIP evidence 集約は KUU-1617 が担当する。
本監査でこれらの実装・検証を完了済みに変更しない。

## 9. 再現と検証範囲

再採取コマンドと必要な toolchain は
[`fixtures/js_annotations/README.md`](fixtures/js_annotations/README.md) を参照。
raw 結果と期待値の参照先を case 単位で固定し、生成した JS / klib は一時ディレクトリへ置く。
23 Kotlin fixture は compile error 13件、warning を伴う受理3件、warning なしの受理7件。
7件の JS link/run と2つの JS consumer を採取し、固定期待値と比較した。
製品 API、Runtime/ABI、既存 runner、元ケース/SKIP タグはこの変更の対象外。
`swift build` は成功（44.41秒）。全テスト・全 Golden・全 diff、
KSwiftK source injection / `.kklib` / O0/O2 は未実行。
