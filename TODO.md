# Kotlin Compiler Remaining Tasks

最終更新: 2026-06-28

---

## 使い方（簡略）
- `[ ]` は未完了、`[~]` は部分完了（本文に残タスクを記載）
- `kotlin.*` の common / Kotlin/Native 相当を主対象とする
- JVM/JS/JVM専用・`kotlinx`・プラグイン系は「ターゲット外バックログ」へ
- 参照は必要最小に留め、詳細は都度 task 本文に反映する

### 主要参照
- Kotlin stdlib 2.3.10 API: https://kotlinlang.org/api/core/kotlin-stdlib/
- Kotlin release process: https://kotlinlang.org/docs/releases.html
- Runtime/API 差分は `Scripts/diff_kotlinc.sh` と `RuntimeABISpec` / ABI テストを起点に確認

#### kotlin.text 関数の実装
- [x] STDLIB-TEXT-FN-048: `reduceIndexedOrNull` 関数の実装

### Phase 4: リフレクション・数値・テキスト・その他 stdlib

#### kotlin.random 関数の実装

- [~] STDLIB-CORO-001: `kotlin.coroutines.intrinsics` / cancellation — 主要部分実装済み（`suspendCoroutineUninterceptedOrReturn`, `intercepted`, `CancellationException`）。残課題は別チケットへ分割。

### Phase 5: 非スコープ/高度領域
- [ ] STDLIB-JS-COLLECTIONS-FN-005: `JsReadonlySet<E>.toMutableSet()` を追加する
- [x] STDLIB-CINTEROP-FN-026: `ULongArray.toCValues()` を追加する
- [x] STDLIB-CINTEROP-FN-041: `CValue<T>.useContents(block)` を追加する
- [x] STDLIB-CINTEROP-FN-042: `T.usePinned(block)` を追加する
- [x] STDLIB-CINTEROP-FN-045: `CValue<T>.write(location)` を追加する
- [ ] STDLIB-JVM-166: Java プレビュー機能の実装
- [ ] STDLIB-REFL-175: アノテーション処理高度機能実装

## Kotlin Stdlib Source Migration（Stdlib/ 層への移行）

PR #3754 で導入した `Stdlib/` ディレクトリへの移行パターン（Kotlin ソースで公開 API を定義し、ネイティブ操作は `kswiftk.internal.*` ブリッジに委譲）を残りの stdlib 領域にも適用する。各タスクは対応する Runtime Swift ファイルのロジックを `Stdlib/*.kt` へ移し、コンパイラの call dispatch を新しい flat/source API 経路に接続する作業を含む。

> **実行タスクは「Stdlib Kotlin 化 実行計画（KSP）」セクションに Haiku 実行可能粒度で細分化済み**（2026-07-01）。本セクションの M/MIGRATION 番号は分類ラベルとして残し、着手は対応する KSP-* から行う。

### 移行方針
- 純ロジック（イテレーション・変換・比較等）は **Kotlin のみ** で実装する
- OS/ハードウェアアクセスが必要な箇所は `__` prefix ブリッジ経由で RuntimeABI に委譲する
- 既存の `kk_*` ABI 関数は bridge として存続し、Kotlin 層からのみ呼ばれる形にする
- String 同様に boxed 表現を flat/aggregate 表現に段階的に移行する

### Phase M1: kotlin.text 残りの String 操作
> 移行元: `Sources/Runtime/RuntimeStringStdlib.swift` (211 @_cdecl)
> 移行先: `Stdlib/kotlin/text/`

- [ ] MIGRATION-TEXT-008: String HOF 関数を Kotlin source に移行する（`filter`, `filterNot`, `filterIndexed`, `map`, `mapIndexed`, `mapNotNull`, `flatMap`, `fold`, `reduce`, `scan` 等）

### Phase M2: kotlin.text StringBuilder
> 移行元: `Sources/Runtime/RuntimeStringBuilder.swift` (29 @_cdecl)
> 移行先: `Stdlib/kotlin/text/StringBuilder.kt`


### Phase M3: kotlin.collections ファクトリ・HOF
> 移行元: `Sources/Runtime/RuntimeCollectionHOF.swift` (166), `RuntimeCollectionHOFArray.swift` (27), `RuntimeCollectionHOFGrouping.swift` (11), `RuntimeCollectionHOFMaxMin.swift` (26), `RuntimeCollections.swift` (85)
> 移行先: `Stdlib/kotlin/collections/`

- [ ] MIGRATION-COL-003: List フィルタ HOF を Kotlin source に移行する（`filter`, `filterNot`, `filterNotNull`, `filterIndexed`, `filterIsInstance`）

### Phase M4: kotlin.sequences
> 移行元: `Sources/Runtime/RuntimeSequence.swift` (105), `RuntimeSequenceBuilders.swift` (20), `RuntimeSequenceAssociation.swift` (25), `RuntimeSequenceFoldScan.swift` (9)
> 移行先: `Stdlib/kotlin/sequences/`

- [ ] MIGRATION-SEQ-004: Sequence 集約 HOF を Kotlin source に移行する（`fold`, `reduce`, `scan`, `associate`, `associateBy`, `groupBy`, `sumOf`, `maxByOrNull`, `minByOrNull`）
- [ ] MIGRATION-SEQ-005: Sequence ウィンドウ・制限 HOF を Kotlin source に移行する（`take`, `takeWhile`, `drop`, `dropWhile`, `chunked`, `windowed`, `zip`, `zipWithNext`, `distinct`, `distinctBy`）

### Phase M5: kotlin.comparisons
> 移行元: `Sources/Runtime/RuntimeComparator.swift` (47 @_cdecl)
> 移行先: `Stdlib/kotlin/comparisons/Comparisons.kt`

- [x] MIGRATION-COMP-001: Comparator ファクトリ・合成を Kotlin source に移行する（`compareBy`, `compareByDescending`, `naturalOrder`, `reverseOrder`, `reversed`, `thenBy`, `thenByDescending`, `thenComparing`）
- [ ] MIGRATION-COMP-002: maxOf/minOf 全オーバーロードを Kotlin source に移行する（Comparable版, プリミティブ版, vararg版）

### Phase M6: kotlin.ranges
> 移行元: `Sources/Runtime/RuntimeRangeAndDispatch.swift` (46), `RuntimeRangeIntRangeHOF.swift` (30), `RuntimeRangeLongRange.swift`, `RuntimeRangeUIntULongRange.swift`
> 移行先: `Stdlib/kotlin/ranges/`

- [x] MIGRATION-RANGE-001: Range/Progression クラス API を Kotlin source に移行する（`IntRange`, `LongRange`, `CharRange`, `IntProgression`, `LongProgression`, `CharProgression` の iterator/contains/isEmpty）
- [ ] MIGRATION-RANGE-002: Range HOF を Kotlin source に移行する（`forEach`, `map`, `filter`, `toList`, `count`, `first`, `last`, `reversed`, `step`）
- [x] MIGRATION-RANGE-003: Range ユーティリティを Kotlin source に移行する（`coerceIn`, `coerceAtLeast`, `coerceAtMost`）— `until`/`downTo` は MIGRATION-RANGE-001 完了後に対応（IntRange/IntProgression 型移行が前提）

### Phase M7: kotlin.random
> 移行元: `Sources/Runtime/RuntimeRandom.swift` (38 @_cdecl)
> 移行先: `Stdlib/kotlin/random/Random.kt`


### Phase M8: kotlin.time / Duration
> 移行元: `Sources/Runtime/RuntimeDuration.swift` (61 @_cdecl)
> 移行先: `Stdlib/kotlin/time/Duration.kt`

- [ ] MIGRATION-TIME-001: `Duration` 算術・変換を Kotlin source に移行する（`plus`, `minus`, `times`, `div`, `unaryMinus`, `absoluteValue`, `isPositive`, `isNegative`, `isInfinite`）

### Phase M12: kotlin.uuid
> 移行元: `Sources/Runtime/RuntimeUuid.swift` (24 @_cdecl)
> 移行先: `Stdlib/kotlin/uuid/Uuid.kt`

- [ ] MIGRATION-UUID-001: `Uuid` クラス API を Kotlin source に移行する（`Uuid.random`, `Uuid.parse`, `toString`, `toLongs`, `toByteArray`）

### Phase M13: kotlin (Result)
> 移行元: `Sources/Runtime/RuntimeResult.swift` (16 @_cdecl)
> 移行先: `Stdlib/kotlin/Result.kt`

- [ ] MIGRATION-RESULT-001: `Result` クラスと `runCatching` を Kotlin source に移行する（`isSuccess`, `isFailure`, `getOrNull`, `getOrDefault`, `getOrElse`, `getOrThrow`, `map`, `fold`, `onSuccess`, `onFailure`）

## Stdlib Kotlin 化 実行計画（KSP）

> RF-STDLIB / M1–M17 / MIGRATION-* の**実行体**。設計: [`docs/stdlib-pipeline.md`](docs/stdlib-pipeline.md)。棚卸し日: 2026-07-01（シンボル名は当日時点の実コードで検証済み。行番号は書かない — アンカーは必ず rg で引く）。
> 依存: W0 → W1 → W2 は直列。W3 以降は「前提」欄に従い並列可。
>
> **共通ゲート G**（全タスクの完了条件に含む）: `bash Scripts/swift_test.sh` / `bash Scripts/swift_test.sh --filter Golden` / `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` すべて green。`Scripts/loc_report.sh` が存在する場合、`HeaderHelpers+Synthetic*` 行数・`"kk_` リテラル数の悪化なし。
> **golden 更新 U**: `UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6` → `git diff -- Tests/CompilerCoreTests/GoldenCases` が機械的差分のみであること。
> **移行テンプレート T**（W2〜W4 の各タスクはこの手順）:
> 1. タスク記載の diff ケースを `Scripts/diff_cases/` で確認・なければ追加し、**現行実装**で `bash Scripts/diff_kotlinc.sh Scripts/diff_cases/<case>.kt` green を確認（挙動の固定）
> 2. タスク記載の実装先 .kt に Kotlin 実装を書く（既存ファイル追記可）。ランタイム依存点は `@KsSymbolName("__kk_...") internal external fun __名前(...)` で宣言
> 3. 新規 .kt は `Sources/CompilerCore/Stdlib/kotlin/` 配下に置くだけで自動配線される。除外リスト対象は `Sources/CompilerCore/Driver/FrontendPhases.swift` の `excludedBundledStdlibFiles` から該当エントリを削除
> 4. **同一 PR** で、タスク記載の (a) `HeaderHelpers+Synthetic*` の該当登録 (b) `CallTypeChecker+*` / `CallLowerer+*` の名前文字列特例 case (c) Runtime の `@_cdecl` 関数 (d) `RuntimeABISpec` の該当エントリ（parity テスト含む）を削除する。「ブリッジ残留」指定の関数は削除せず `__kk_` prefix へ改名し spec を更新
> 5. U → G → タスク記載の rg 完了チェックが 0 件

### KSP-W0: 基盤（RF-STDLIB-003/006/007 の細分化。直列で実施）

- [ ] KSP-001: bundled 宣言インデックスを構築する
  - 前提: なし
  - 変更: 新規 `Sources/CompilerCore/Sema/DataFlow/BundledDeclarationIndex.swift` / `Sources/CompilerCore/Sema/DataFlow/Phase.swift` / `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers.swift` の `registerSyntheticDelegateStubs(symbols:types:interner:)`
  - 手順: (0) `Phase.swift` の `run()` で bundled ソース宣言の SymbolTable 登録が `registerSyntheticDelegateStubs` 呼び出しより先であることを確認（先でなければ中断して報告） (1) パスが `__bundled_` で始まる fileID 集合を `ctx.sourceManager` から取り、`declSite` がそこに属す関数/プロパティの `(所有型FQName, メンバ名, パラメータ数)` Set を持つ struct `BundledDeclarationIndex` を実装（member lookup の型は `SymbolTable.lookupAll(fqName:)` / `Helpers+TypeArgsAndMemberLookup.swift` の `lookupMemberProperty` を参照） (2) `registerSyntheticDelegateStubs` に引数 `bundledIndex`（既定 `.empty`）を追加し `Phase.swift` から渡す
  - 検証: `swift build` + G（このタスクでは挙動不変）
- [ ] KSP-002: 優先規則（Kotlin ソース > 合成スタブ）を実装する
  - 前提: KSP-001
  - 変更: `HeaderHelpers.swift` と各 `HeaderHelpers+Synthetic*` が使う共通登録ヘルパ
  - 手順: (1) `rg -n 'func register' Sources/CompilerCore/Sema/DataFlow/HeaderHelpers.swift` で、メンバ/トップレベル関数シンボルを SymbolTable へ insert する共通ヘルパを特定 (2) insert 直前に `bundledIndex` に同 `(owner, name, arity)` があれば登録をスキップ (3) スキップ件数を debug ログ可能にする
  - 検証: G + U（bundled 由来 API のスタブが消えるため Sema golden 差分が出る — 機械的差分であることを確認）
  - 完了: `BundledKotlinStdlib.kotlinCollectionsSource` の `count`/`any`/`all` に対応する合成スタブが登録されないことをテストで assert
- [ ] KSP-003: 二重定義 warning 診断を追加する
  - 前提: KSP-002
  - 変更: `Sources/CompilerCore/Driver/DiagnosticRegistry.swift` の `semaDescriptors` / `Phase.swift`
  - 手順: (1) `rg 'KSWIFTK-SEMA-' Sources/CompilerCore/Driver/DiagnosticRegistry.swift` で未使用番号を採番し descriptor 追加 (2) `registerSyntheticDelegateStubs` 完了後、bundled インデックスと `.synthetic` フラグ付きシンボルの `(owner, name, arity)` 交差を検出したら `ctx.diagnostics.warning(...)`（= KSP-002 のガード漏れ検知） (3) 診断テスト追加
  - 検証: G
- [ ] KSP-004: bundled ソースの fileID 順序不変条件テストを追加する
  - 前提: なし（並列可）
  - 変更: 新規 `Tests/CompilerCoreTests/Driver/BundledStdlibOrderingTests.swift`
  - 手順: `LoadSourcesPhase` 実行後の `sourceManager.fileIDs()` について (a) `__bundled_*` がユーザー入力より前 (b) `__bundled_*` 同士が相対パス辞書順、を assert
  - 検証: G
- [ ] KSP-005: golden Sema ダンプから bundled 由来シンボルを除外する
  - 前提: KSP-004
  - 変更: `Sources/GoldenHarnessSupport/GoldenHarnessDump.swift` の `dumpSema(sourcePath:)`
  - 手順: `Sources/CompilerCore/Sema/Models/MetadataSerializer.swift` の `buildRecords` にある excludedFileIDs（`__bundled_*` の declSite 除外）と同じフィルタを dumpSema に適用 → U で一括更新
  - 完了: `rg '__bundled_' Tests/CompilerCoreTests/GoldenCases` が 0 件 + G
- [ ] KSP-006: bundled stdlib のコンパイル時間を PhaseTimer で分離計測する
  - 前提: なし（並列可）
  - 変更: `Sources/CompilerCore/Driver/FrontendPhases.swift`（Lex/Parse ループ）。`PhaseTimer.swift` は変更不要（`recordSubPhase(_:startTime:endTime:)` を利用）
  - 手順: Lex/Parse（および可能なら Sema）で `__bundled_` プレフィックス fileID の処理時間を集計し、各フェーズに `recordSubPhase("bundled-stdlib", ...)` を記録
  - 検証: G + タイミング出力に bundled-stdlib 行が出ること
- [ ] KSP-007: bundled 注入コストのベースラインを記録する
  - 前提: KSP-006
  - 変更: `docs/refactoring-metrics.md`
  - 手順: (1) `rg -n 'phaseRecords' Sources` で PhaseTimer 出力の表示経路を確認 (2) `.build/debug/kswiftc Scripts/diff_cases/hello.kt -o /tmp/ksp_out` で計測 3 回の中央値を取得 (3) 「bundled stdlib 注入コスト」節を追記し、キャッシュ着手トリガー閾値（+100ms）を正式化
- [ ] KSP-008: 設計文書の opt-out フラグ名を実装に合わせる
  - 前提: なし（並列可）
  - 変更: `docs/stdlib-pipeline.md` §4
  - 手順: `-no-default-stdlib-sources` の記述を実名 `--no-stdlib`（`Sources/KSwiftKCLI/CLIParser.swift` / `CompilerOptions.includeStdlib`）へ修正

### KSP-W1: @KsSymbolName ブリッジ機構（W0 完了後、直列）

- [ ] KSP-101: `@KsSymbolName` 注釈と Sema での externalLinkName 記録を実装する
  - 前提: KSP-002
  - 変更: 新規 `Sources/CompilerCore/Stdlib/kotlin/internal/Annotations.kt`（`package kotlin.internal` / `internal annotation class KsSymbolName(val name: String)`）/ Sema のヘッダ収集（関数シンボル生成箇所）
  - 手順: (1) `rg -n 'setExternalLinkName' Sources/CompilerCore` で既存の記録パターンを確認（`SemanticsModels.swift` の `setExternalLinkName(_:for:)`） (2) `FunctionDecl.annotations`（`AnnotationNode(name:arguments:)`）に `KsSymbolName` があれば引数文字列（引用符除去）を externalLinkName として記録 (3) 記録された関数の呼び出しが KIR で当該シンボル名の外部 call になるユニットテスト追加
  - 検証: G
- [ ] KSP-102: `external fun` の本体なしを検証する
  - 前提: KSP-101
  - 手順: (1) `external` 修飾子付き fun（本体なし）が診断なしで通ることを確認（出る場合は body-required 診断を external 免除に） (2) `external` なし・本体なし fun がエラーのままであることをテストで固定
  - 検証: G
- [ ] KSP-103: @KsSymbolName ↔ RuntimeABISpec 突合テストを追加する
  - 前提: KSP-101
  - 変更: 新規テスト（`Tests/` 配下、`RuntimeABIExternalLinkValidationTests` のパターンを流用）
  - 手順: bundled 全 .kt から `@KsSymbolName\("([^"]+)"\)` を抽出し、全値が `RuntimeABISpec` に宣言されアリティが一致することを assert（enforcing）
  - 検証: G
- [ ] KSP-104: `@KsSymbolName` / `external` のユーザーコード使用を禁止する
  - 前提: KSP-101
  - 変更: Sema + `DiagnosticRegistry.swift`（KSWIFTK-SEMA 新番号）
  - 手順: 宣言ファイルのパスが `__bundled_` で始まらない場合に error 診断。テスト追加
  - 検証: G

### KSP-W2: 縦切りテンプレート（1 タスク = 1 PR。以後の移行の見本）

- [ ] KSP-201: StringComparison 縦切り（`commonPrefixWith`/`commonSuffixWith`）[RF-STDLIB-004]
  - 前提: KSP-002, KSP-005
  - 実装先: `Sources/CompilerCore/Stdlib/kotlin/text/StringComparison.kt`（実装済み・配線済み。優先規則で解決されることの確認から）
  - 削除: `CallTypeChecker+MemberCallInferenceRegularNoCandidateFallbacks.swift` の `commonPrefixWith`/`commonSuffixWith` 特例 3 箇所（`rg -n 'commonPrefixWith' Sources/CompilerCore`）/ `CallLowerer+StringStdlibMemberCalls.swift` の同 case / `RuntimeStringHOF.swift` の `kk_string_commonPrefixWith`, `kk_string_commonPrefixWith_ignoreCase`, `kk_string_commonSuffixWith`, `kk_string_commonSuffixWith_ignoreCase` / `RuntimeABISpec.swift` の同 4 エントリ
  - diff: `string_common_prefix_suffix.kt` を新規追加（ignoreCase 込み）
  - 手順: T / 完了: `rg 'commonPrefixWith|commonSuffixWith' Sources/CompilerCore Sources/Runtime Sources/RuntimeABI` が Stdlib/*.kt 以外 0 件 + G
- [ ] KSP-202: StringSplitJoin 縦切り（初の除外リスト解消 + `__kk_` 降格）[RF-STDLIB-005]
  - 前提: KSP-201, KSP-101
  - 手順: T。`excludedBundledStdlibFiles` から `kotlin/text/StringSplitJoin` を削除
  - 対象 kk_*: `kk_string_split`, `kk_string_split_limit`, `kk_string_splitToSequence`, `kk_string_joinToString`（完全 Kotlin 化を優先。性能上必要なら単一デリミタ高速路のみ `__kk_string_split` へ降格し `@KsSymbolName` で利用）
  - 削除: `HeaderHelpers+SyntheticStringStubs.swift` の split/joinToString 登録 / `CallLowerer+StringStdlibMemberCalls.swift` の同 case
  - diff: `ls Scripts/diff_cases | rg 'split|join'` で既存確認、limit・ignoreCase ケースがなければ追加
  - 完了: `rg '"kk_string_split|"kk_string_joinToString' Sources/CompilerCore` 0 件 + G

### KSP-W3: excludedBundledStdlibFiles 解消（前提: KSP-202。相互独立・並列可）

- [ ] KSP-301: ゴーストエントリ 5 件を削除する
  - 手順: `FrontendPhases.swift` の `excludedBundledStdlibFiles` から、実ファイルが存在しない `kotlin/ResultExtensions`, `kotlin/logging/AdvancedLogger`, `kotlin/reflect/KClassAnnotationRegistration`, `kotlin/text/StringBasics`, `kotlin/text/StringEncoding` を削除（`find Sources/CompilerCore/Stdlib -name '*.kt'` で不在を確認してから）
  - 検証: G のみ
- [ ] KSP-302: StringIndentFormat を配線する（`trimIndent`/`trimMargin`/`prependIndent`/`replaceIndent`/`replaceIndentByMargin`）
  - 注意: **同一 PR で** `BundledKotlinStdlib.kotlinTextSource` 内の同名 5 関数を削除（二重定義になるため）。runtime `__string_trimIndent` 系 / `kk_string_trimIndent` 系（`RuntimeStringFormat.swift`）は Kotlin 版が完全なら削除、不足なら `__kk_` 降格
  - 手順: T / diff: `string_indent.kt`（既存）
- [ ] KSP-303: StringSearchReplace を配線する（`replace`×3, `replaceFirst`×3, split(regex) 等）
  - 削除: `kk_string_replace`, `kk_string_replace_char`, `kk_string_replace_ignoreCase`, `kk_string_replace_char_ignoreCase`, `kk_string_replaceFirst`, `kk_string_replaceFirst_ignoreCase`（`RuntimeStringStdlib.swift`/`RuntimeStringSubstring.swift`）+ `HeaderHelpers+SyntheticStringStubs.swift` / `CallLowerer+StringStdlibMemberCalls.swift` の該当 case
  - 手順: T
- [ ] KSP-304: Result を配線する（クラス本体 + `runCatching` ほか全 16 API）
  - 注意: スタブがヘッダ収集前に Result クラスを登録して二重定義になる既知問題 → KSP-002 の優先規則がクラス宣言にも効くことを先に確認
  - 削除: `HeaderHelpers+SyntheticResultStubs.swift` 全体 / `RuntimeResult.swift` の `kk_result_*` 15 関数 + `kk_runCatching` / `CallLowerer+MemberCalls.swift` の Result 特例
  - 手順: T / diff: `result_advanced.kt`（既存）+ recover/recoverCatching ケース追加
- [ ] KSP-305: CollectionFactories を配線する（`listOf`/`setOf`/`mapOf`/`empty*`/`mutable*Of`）
  - 注意: `CollectionLiteralLoweringPass` がファクトリ呼び出しを直接 `kk_*` へ書き換えている。ブリッジ残留: 生成コア `kk_list_of`, `kk_set_of`, `kk_map_of`, `kk_emptyList`, `kk_emptySet`, `kk_emptyMap` は `__kk_` 降格（アロケーション主体のため）
  - 削除: `CallLowerer+StdlibArrayConstructor.swift` のファクトリ特例 / 各 `HeaderHelpers+Synthetic{List,Set,Map,Array}Stubs.swift` のファクトリ登録
  - 手順: T / diff: `collection_builders.kt`（既存）
- [ ] KSP-306: ListFilterHOF を配線する（`filter`, `filterNot`, `filterNotNull`, `filterIndexed`, `filterIsInstance`）
  - 削除: `kk_list_filter`, `kk_list_filterNot`, `kk_list_filterNotNull`, `kk_list_filterIndexed`, `kk_list_filterIsInstance` + `*To` 変種（`RuntimeCollectionHOF.swift`）/ `HeaderHelpers+SyntheticListTransformMembers.swift` の同登録 / `CallLowerer+CollectionHOFMemberCalls.swift` の同 case
  - 手順: T
- [ ] KSP-307: ListWindowChunk を配線する（`chunked`, `windowed`, `zip`, `zipWithNext`, `withIndex`）
  - 削除: `kk_list_chunked`, `kk_list_chunked_transform`, `kk_list_windowed`, `kk_list_windowed_default`, `kk_list_windowed_partial`, `kk_list_windowed_transform`, `kk_list_zip`, `kk_list_zipWithNext`, `kk_list_zipWithNextTransform` / 対応スタブ（`HeaderHelpers+SyntheticListTransformMembers.swift`, `+SyntheticListAggregateMembers.swift`）
  - 手順: T
- [ ] KSP-308: SequenceWindowChunk を配線する（`take`, `takeWhile`, `drop`, `dropWhile`, `chunked`, `windowed`, `zip`, `zipWithNext`, `distinct`, `distinctBy`）
  - 前提: KSP-441（Sequence 遅延パイプラインの Kotlin 表現）。それまで着手不可
  - 削除: `kk_sequence_take`, `kk_sequence_takeWhile`, `kk_sequence_drop`, `kk_sequence_dropWhile`, `kk_sequence_chunked`, `kk_sequence_chunked_transform`, `kk_sequence_windowed`, `kk_sequence_windowed_transform`, `kk_sequence_zip`, `kk_sequence_zipWithNext`, `kk_sequence_zipWithNextTransform`, `kk_sequence_distinct`, `kk_sequence_distinctBy`（`RuntimeSequence.swift`）/ `HeaderHelpers+SyntheticSequenceTerminalStubs.swift` の同登録
- [ ] KSP-309: Comparators を配線する（死蔵 `Stdlib/kotlin/comparisons/Comparators.kt` を `Sources/CompilerCore/Stdlib/kotlin/comparisons/` へ移設して配線）
  - 対象: `compareBy`×2, `compareByDescending`×2, `naturalOrder`, `reverseOrder`, `reversed`, `thenBy`, `thenByDescending`, `thenComparing`
  - 削除: `RuntimeComparator.swift` の対応 `kk_comparator_*`（trampoline 含む）/ `HeaderHelpers+SyntheticComparatorStubs.swift` の同登録 / `CallLowerer+StdlibComparisons.swift` の同 case
  - 注意: Comparator SAM ディスパッチ対応が前提（未対応ならブロッカーとして報告）/ diff: `comparisons_edge_cases.kt`（既存）
- [ ] KSP-310: Uuid を配線する（`random`, `parse*`, `toString`, `toHexString`, `toLongs`, `toByteArray`, `fromLongs`, `fromByteArray`, `version`, `variant` 等）
  - ブリッジ残留: `kk_uuid_random`（エントロピー）と `kk_uuid_nameUUIDFromBytes`（MD5）は `__kk_` 降格。パース/整形/ビット抽出は Kotlin 化
  - 削除: `HeaderHelpers+SyntheticUuidStubs.swift` の該当登録 / `RuntimeUuid.swift` の純ロジック系 `kk_uuid_*` / diff: `uuid_basic.kt`（既存）
  - 手順: T
- [ ] KSP-311: StringBuilder を配線する（クラス + `append`系/`insert`/`delete`系/`reverse`/`toString` 等 34 関数）
  - 注意: コンストラクタは `CallSupportLowerer` 経由。可変内部バッファは `__kk_` ブリッジ最小集合（new/append_obj/toString/length など）に絞り、型別 append/insert/delete 系を Kotlin 化
  - 削除対象の確認: `rg -n 'kk_string_builder_' Sources/Runtime/RuntimeStringBuilder.swift Sources/CompilerCore` で全列挙 → 残留/削除を分類してから着手
  - 手順: T / diff: `ls Scripts/diff_cases | rg -i 'builder'` で確認・不足追加
- [ ] KSP-312: RangeIterators / RangeMembership を配線する（`iterator`/`contains`/`isEmpty` 各 Range/Progression）
  - 注意: `for (x in range)` は `ExprLowerer+ControlFlowAndBlocks.swift` が `.iterator()` を経由せず `kk_range_iterator`/`hasNext`/`next` へ直接特例化している（3 並列ディスパッチ）。本タスクは (1) 死蔵 2 ファイルの移設・配線 (2) `CallTypeChecker+RangeMemberFallback.swift` の該当特例削除まで。for-in 特例の撤去は KSP-452 で実施
  - 手順: T / diff: `range_basic.kt`, `range_contains.kt`（既存）

### KSP-W4: モジュール量産移行（各タスク = 1 PR。手順はすべて T）

#### kotlin.text [M1/M2 実行体]（前提: KSP-202。実装先は原則 `Sources/CompilerCore/Stdlib/kotlin/text/` の既存ファイルへ追記、なければ本家準拠名で新規）

- [ ] KSP-401: empty/blank/lines 系を Kotlin 化（`isEmpty`, `isNotEmpty`, `isBlank`, `isNotBlank`, `isNullOrEmpty`, `isNullOrBlank`, `ifEmpty`, `ifBlank`, `orEmpty`, `lines`, `lineSequence`）
  - 削除 kk_*: `kk_string_isEmpty`, `kk_string_isNotEmpty`, `kk_string_isBlank`, `kk_string_isNotBlank`, `kk_string_ifBlank`, `kk_string_ifEmpty`, `kk_string_orEmpty`, `kk_string_isNullOrEmpty`, `kk_string_isNullOrBlank`, `kk_string_lines`, `kk_string_lineSequence`（`RuntimeStringQuery.swift`）
  - 完了: `rg '"kk_string_is|"kk_string_if|"kk_string_orEmpty|"kk_string_lines' Sources/CompilerCore` 0 件 + G
- [ ] KSP-402: first/last/single 系を Kotlin 化（`first`, `last`, `single`, `firstOrNull`, `lastOrNull`, `singleOrNull`, `getOrNull` + predicate 版）
  - 削除 kk_*: `kk_string_first`, `kk_string_last`, `kk_string_single`, `kk_string_firstOrNull`, `kk_string_lastOrNull`, `kk_string_singleOrNull`, `kk_string_getOrNull`, `kk_string_singleOrNull_predicate`（`RuntimeStringQuery.swift`）
- [ ] KSP-403: trim 系を Kotlin 化（`trim`, `trimStart`, `trimEnd` + predicate 版）
  - 削除 kk_*: `kk_string_trim`, `kk_string_trim_predicate`, `kk_string_trimStart`, `kk_string_trimStart_predicate`, `kk_string_trimEnd`, `kk_string_trimEnd_predicate` / diff: `string_trimstart_trimend.kt`（既存）+ predicate 版追加
- [ ] KSP-404: prefix/suffix 系を Kotlin 化（`startsWith`, `endsWith`, `removePrefix`, `removeSuffix`, `removeSurrounding`）
  - 削除 kk_*: `kk_string_startsWith`, `kk_string_endsWith`, `kk_string_removePrefix`, `kk_string_removeSuffix`, `kk_string_removeSurrounding`, `kk_string_removeSurrounding_pair`
- [ ] KSP-405: take/drop 系を Kotlin 化（`take`, `takeLast`, `drop`, `dropLast`, `takeWhile`, `dropWhile`, `takeLastWhile`）
  - 削除 kk_*: `kk_string_take`, `kk_string_takeLast`, `kk_string_drop`, `kk_string_dropLast`, `kk_string_takeWhile`, `kk_string_dropWhile`, `kk_string_takeLastWhile`
- [ ] KSP-406: substring/slice/range 編集系を Kotlin 化（`substring`, `subSequence`, `slice`, `removeRange`, `replaceRange`）
  - 削除 kk_*: `kk_string_substring`, `kk_string_subSequence`, `kk_string_slice_range`, `kk_string_slice_iterable`, `kk_string_removeRange`, `kk_string_removeRange_range`, `kk_string_replaceRange`, `kk_string_replaceRange_indices`（`RuntimeStringStdlib.swift`/`RuntimeStringSubstring.swift`）。基点の `substring(startIndex, endIndex)` のみ `__kk_` 降格可
- [ ] KSP-407: substringBefore/After・replaceBefore/After 系を Kotlin 化（各 String/Char 版）
  - 削除 kk_*: `kk_string_substringBefore(_char)`, `kk_string_substringAfter(_char)`, `kk_string_substringBeforeLast(_char)`, `kk_string_substringAfterLast(_char)`, `kk_string_replaceAfter(_char)`, `kk_string_replaceAfterLast(_char)`, `kk_string_replaceBefore(_char)`, `kk_string_replaceBeforeLast(_char)`（`RuntimeStringSubstring.swift`、計 16）
- [ ] KSP-408: contains/indexOf 系を Kotlin 化（`contains`, `indexOf`, `lastIndexOf`, `indexOfAny`, `lastIndexOfAny`, `findAnyOf`, `findLastAnyOf`, `indexOfFirst`, `indexOfLast` + ignoreCase/from 版）
  - 削除 kk_*: `kk_string_contains_str`, `kk_string_contains_ignoreCase`, `kk_string_indexOf`, `kk_string_indexOf_from`, `kk_string_indexOf_char`, `kk_string_indexOf_ignoreCase`, `kk_string_lastIndexOf`, `kk_string_lastIndexOf_char`, `kk_string_lastIndexOf_ignoreCase`, `kk_string_indexOfAny_chars`, `kk_string_indexOfAny_strings`, `kk_string_lastIndexOfAny_chars`, `kk_string_lastIndexOfAny_strings`, `kk_string_findAnyOf`, `kk_string_findLastAnyOf`, `kk_string_indexOfFirst`, `kk_string_indexOfLast`（`RuntimeStringStdlib.swift`/`RuntimeStringSearch.swift`）
- [ ] KSP-409: コレクション変換・iterator 系を Kotlin 化（`toList`, `toMutableList`, `toCharArray`, `toTypedArray`, `toCollection`, `toSortedSet`, `iterator`, `asIterable`, `asSequence`, `withIndex`）
  - 削除 kk_*: `kk_string_toList`, `kk_string_toMutableList`, `kk_string_toCharArray`, `kk_string_toTypedArray`, `kk_string_toCollection`, `kk_string_toSortedSet`, `kk_string_iterator`, `kk_string_iterator_hasNext`, `kk_string_iterator_next`, `kk_string_asIterable`, `kk_string_iterable_toList`, `kk_string_iterable_iterator`, `kk_string_asSequence`, `kk_string_withIndex`
- [ ] KSP-410: String HOF を Kotlin 化 [MIGRATION-TEXT-008]（`filter(Not/Indexed)`, `map(Indexed/NotNull)`, `any`, `all`, `none`, `count`, `fold`系, `reduce`系, `find(Last)`, `onEach(Indexed)`, `partition`, `sumBy(Double)`, `firstNotNullOf(OrNull)`）
  - 削除 kk_*: `RuntimeStringHOF.swift` の該当約 27 関数（`rg -o '@_cdecl\("kk_string_[a-zA-Z]+"\)' Sources/Runtime/RuntimeStringHOF.swift` で着手時に全列挙して固定）
- [ ] KSP-411: chunked/windowed/zip 系を Kotlin 化
  - 削除 kk_*: `kk_string_chunked`, `kk_string_chunked_sequence`, `kk_string_chunked_sequence_transform`, `kk_string_windowed_default`, `kk_string_windowed`, `kk_string_windowed_partial`, `kk_string_windowedSequence_partial`, `kk_string_windowedSequence_transform`, `kk_string_zip`, `kk_string_zipTransform`, `kk_string_zipWithNext`, `kk_string_zipWithNextTransform`
- [ ] KSP-412: case 変換を完遂する（`capitalize`, `replaceFirstChar` を Kotlin 化、locale 版は `__kk_` 降格）
  - 既存 `StringCaseConversion.kt` が `__kk_lowercase_locale`/`__kk_uppercase_locale` 委譲パターンの見本
  - 削除 kk_*: `kk_string_capitalize`, `kk_string_replaceFirstChar` / 降格: `kk_string_lowercase_locale`, `kk_string_uppercase_locale`
- [ ] KSP-413: 比較系を Kotlin 化（`compareToIgnoreCase`, `contentEquals`, `equals(ignoreCase)`）
  - 削除 kk_*: `kk_string_compareToIgnoreCase`, `kk_string_contentEquals`, `kk_string_contentEquals_ignoreCase` / 降格: `kk_string_compareTo_locale`（locale 依存）
- [ ] KSP-414: 数値パース（整数 radix 系）を Kotlin 化（`toInt(OrNull)(radix)`, `toLong…`, `toShort…`, `toByte…`, `toU*OrNull(radix)`, `toBoolean(Strict)(OrNull)`）
  - 削除 kk_*: `RuntimeStringConversion.swift` の該当関数（`rg -o '@_cdecl\("kk_string_to[A-Z][a-zA-Z]*(_radix)?"\)' Sources/Runtime/RuntimeStringConversion.swift` で列挙し Float/Double/BigDecimal/BigInteger を除く）
- [ ] KSP-415: 浮動小数・BigNum パースを `__kk_` 降格する（`toFloat(OrNull)`, `toDouble(OrNull)`, `toBigDecimal*`, `toBigInteger*`）
  - Foundation 依存のためブリッジ残留。`kk_string_toFloat*`, `kk_string_toDouble*`, `kk_string_toBigDecimal*`, `kk_string_toBigInteger*`, `kk_bignum_toString` を `__kk_` へ改名し、Kotlin 側 `@KsSymbolName` 宣言経由に置換
- [ ] KSP-416: エンコーディング系を `__kk_` 降格する（`toByteArray`, `encodeToByteArray`, `decodeToString`, `Charsets.*`）
  - トランスコードはブリッジ残留。`kk_charset_*` 9 関数と `kk_string_toByteArray*`, `kk_string_encodeToByteArray*`, `kk_bytearray_decodeToString*`, `kk_byteArray_toKString` を `__kk_` へ改名。公開 API 層（オーバーロード分岐・境界検査・例外）は Kotlin 化。インライン `kotlinTextSource` の同 API と統合（KSP-502 と調整）
- [ ] KSP-417: Unicode 正規化・codePoint・random を `__kk_` 降格する
  - `kk_normalization_form_*` 4 関数, `kk_string_normalize`, `kk_string_isNormalized`, `kk_string_codePointCount*` 3 関数, `kk_string_random(_random)` を `__kk_` へ改名（実装移植はしない）
- [ ] KSP-418: format/indent を完遂する（KSP-302 の残り + `String.format(_locale)` は `__kk_` 降格）
  - 対象: `RuntimeStringFormat.swift` の `kk_string_format`, `kk_string_format_locale`（降格）と残存 `__string_*` 旧ブリッジの命名統一

#### kotlin.collections [M3 実行体]（前提: KSP-305〜307。実装先: `Sources/CompilerCore/Stdlib/kotlin/collections/`）

- [ ] KSP-421: List transform を完遂（`map`, `mapIndexed`, `mapNotNull`, `flatten`, `flatMap(Indexed)` + `*To` 変種）
  - 削除 kk_*: `kk_list_map`, `kk_list_mapIndexed`, `kk_list_mapIndexedTo`, `kk_list_mapNotNull`, `kk_list_mapNotNullTo`, `kk_list_mapTo`, `kk_list_flatten`, `kk_list_flatMap`, `kk_list_flatMapIndexed`, `kk_list_flatMapIndexedTo`, `kk_list_flatMapTo`（`RuntimeCollectionHOF.swift`）
- [ ] KSP-422: List fold/reduce/scan を Kotlin 化（`fold(Right)(Indexed)`, `reduce(Right)(Indexed)(OrNull)`, `runningFold/Reduce(Indexed)`, `scan(Indexed)`）
  - 削除 kk_*: 該当 19 関数（`rg -o '@_cdecl\("kk_list_(fold|reduce|running|scan)[a-zA-Z]*"\)' Sources/Runtime` で列挙）/ 既存 `ListAggregateHOF.kt` に追記
- [ ] KSP-423: List 検索・述語を完遂（`find(Last)`, `indexOf(First/Last)`, `lastIndexOf`, `contains(All)`, `any`, `all`, `none`, `count`, `binarySearch(By)`）
  - 削除 kk_*: `kk_list_find`, `kk_list_findLast`, `kk_list_indexOf`, `kk_list_indexOfFirst`, `kk_list_indexOfLast`, `kk_list_lastIndexOf`, `kk_list_contains`, `kk_list_containsAll`, `kk_list_any`, `kk_list_all`, `kk_list_none`, `kk_list_count`, `kk_list_binarySearch(_comparator/_compare)`, `kk_list_binarySearchBy(_fromIndex/_range)` / 既存 `ListSearchHOF.kt` に追記。等値判定コアは `__kk_values_equal`（新設）へ降格
- [ ] KSP-424: List アクセスを Kotlin 化（`getOrNull`, `getOrElse`, `elementAt(OrNull/OrElse)`, `first(OrNull)`, `last(OrNull)`, `single(OrNull)`）
  - ブリッジ残留: `kk_list_get`, `kk_list_size` は `__kk_` 降格（ストレージ直アクセス）。他は Kotlin 化して削除
- [ ] KSP-425: List associate/group/zip 系を Kotlin 化（`associate(By/With)(To)`, `groupBy(To)`, `withIndex`, `onEach(Indexed)`, `partition`, `unzip`）
  - 削除 kk_*: `rg -o '@_cdecl\("kk_list_(associate|group|withIndex|onEach|partition|unzip)[a-zA-Z]*"\)' Sources/Runtime` で列挙（約 19 関数）
- [ ] KSP-426: List sort/max/min を Kotlin 化（`sorted(By/With/Descending)` + `_primitive` 変種, mutable `sort*`, `max/min(By/Of/With)(OrNull)`）
  - 削除 kk_*: `RuntimeCollectionHOFMaxMin.swift` の sorted 系 18 + max/min 系 20（rg で列挙）。比較コアは KSP-309 の Comparator Kotlin 実装を利用
- [ ] KSP-427: List slice/take/drop を Kotlin 化（`take(Last)(While)`, `drop(Last)(While)`, `slice`, `subList`）
  - 削除 kk_*: `kk_list_take`, `kk_list_takeLast`, `kk_list_takeWhile`, `kk_list_takeLastWhile`, `kk_list_drop`, `kk_list_dropLast`, `kk_list_dropWhile`, `kk_list_dropLastWhile`, `kk_list_slice`, `kk_list_slice_iterable`, `kk_list_subList`
- [ ] KSP-428: List 集合演算・数値系を Kotlin 化（`plus`, `minus`, `intersect`, `union`, `subtract`, `distinct(By)`, `sum(Of/By)`, `average`, `reversed`, `asReversed`）
  - 削除 kk_*: 該当約 18 関数（rg で列挙）。`kk_list_shuffled(_random)` はエントロピー依存のため KSP-466 完了後に Kotlin 化
- [ ] KSP-429: List 変換・joinToString を Kotlin 化（`toMap`, `toSet`, `toHashSet`, `toMutableList/Set`, `joinTo(String)`, `orEmpty`, `component1-5`, `indices`, `lastIndex`, `isEmpty/isNotEmpty`）
  - ブリッジ残留: 新規コレクション生成コアのみ（KSP-305 の `__kk_` 群を利用）
- [ ] KSP-430: Map HOF を Kotlin 化（`filter(Keys/Values/Not)`, `map(NotNull)`, `mapKeys(To)`, `mapValues(To)`, `flatMap`, `forEach`, `any`, `all`, `none`, `count`, `maxByOrNull`, `minByOrNull`, `plus`, `minus`）
  - 削除 kk_*: `RuntimeCollectionHOF.swift` の `kk_map_*` HOF 18 関数 + `RuntimeSetAndMap.swift` の `kk_map_plus`, `kk_map_minus`
- [ ] KSP-431: Map lookup・変換を Kotlin 化（`getValue`, `getOrDefault`, `getOrElse`, `getOrPut`, `containsKey/Value`, `keys`, `values`, `entries`, `toList`, `toMutableMap`, `orEmpty`, `withDefault`）
  - ブリッジ残留: `kk_map_get`（キー探索コア）→ `__kk_map_get`、iterator 状態 → `__kk_map_iterator*`。他は Kotlin 化
- [ ] KSP-432: Set 全般を Kotlin 化（述語 13, HOF 6, `intersect`/`union`/`subtract`, `sorted(Descending)`, `maxOrNull`/`minOrNull`, 変換 4）
  - 既存 `SetHOF.kt` に追記。ブリッジ残留: 要素探索コア等の最小集合を `__kk_` 降格し残りの `kk_set_*` を削除（`rg -o '@_cdecl\("kk_set_[a-zA-Z_]+"\)' Sources/Runtime` で全列挙してから分類）
- [ ] KSP-433: Array HOF を Kotlin 化（`map(NotNull)`, `filter`, `fold(Indexed)`, `flatMap`, `reduce(Indexed)(OrNull)`, `forEach`, `any`, `all`, `none`, `find(Last)`, `count`, `binarySearch`, `sortedArrayWith`, `asSequence`, `joinToString`）
  - 削除 kk_*: `RuntimeCollectionHOFArray.swift` の 20 関数（rg で列挙）
- [ ] KSP-434: Grouping を Kotlin 化（`groupingBy`, `eachCount(To)`, `fold(To)`, `reduce(To)`, `aggregate(To)`）
  - 削除 kk_*: `RuntimeCollectionHOFGrouping.swift` の 11 関数 + `HeaderHelpers+SyntheticGroupingStubs.swift` の該当登録
- [ ] KSP-435: Iterable/Collection 汎用を Kotlin 化（`kk_iterable_*` 12 関数, `kk_collection_*` 6 関数）
  - ブリッジ残留: 型タグディスパッチが必要な `kk_collection_size` 等は `__kk_` 降格を検討（着手時に rg で分類し、分類根拠をタスク PR に記載）
- [ ] KSP-436: 可変操作の最小ブリッジを確定する（MutableList/Set/Map の `add`/`remove`/`clear`/`set`/`put` 系 33 関数）
  - 原則ブリッジ残留（ストレージ直接変異）: `kk_mutable_*` を `__kk_` へ一括改名し、`removeIf`/`retainAll`/`replaceAll`/`fill`/`addAll` 系など述語・複合系のみ Kotlin 化。`CallLowerer+MemberCallEmission.swift` の該当特例を Kotlin 宣言経由に置換

#### kotlin.sequences [M4 実行体]（KSP-441 が先頭。他は 441 完了後に並列可）

- [ ] KSP-441: Sequence 遅延 transform 基盤を Kotlin 化（`Sequence`/`Iterator` インターフェース + `map`, `filter` 系 transform）
  - 注意: object 式（匿名クラス）でパイプラインを表現する。コンパイラの object 式・ジェネリクス対応が不足していれば**ブロッカーとして報告し中断**
  - 対象 kk_*: `RuntimeSequence.swift` の transform 系（`kk_sequence_map*`, `kk_sequence_filter*`, `kk_sequence_withIndex`, `kk_sequence_flatMap*`, `kk_sequence_onEach*`, `kk_sequence_requireNoNulls` 等。rg で全列挙）
- [ ] KSP-442: Sequence terminal を Kotlin 化（`first*`, `last*`, `single*`, `elementAt*`, `find(Last)`, `contains`, `indexOf*`, `any`, `all`, `none`, `count`, `min*`, `max*`, `sum`, `average`）
  - 前提: KSP-441 / 既存 `SequenceAggregateHOF.kt` に追記
- [ ] KSP-443: Sequence 変換・集合演算を Kotlin 化（`toList`, `toMutableList`, `toSet`, `toMutableSet`, `toHashSet`, `toSortedSet`, `toCollection`, `toMap`, `flatten`, `unzip`, `union`, `intersect`, `subtract`, `plus*`, `minus`, `ifEmpty`, `constrainOnce`, `orEmpty`）
  - 注意: インライン `kotlinSequencesSource`（toList/toMutableList/toSet）と統合（KSP-503 と調整）
- [ ] KSP-444: Sequence association・minBy/maxBy を Kotlin 化（`associate*(To)`, `groupBy(To)`, `partition`, `joinTo(String)`, `sumOf/By(Double)`, `min/max(By/Of/With)(OrNull)`）
  - 削除 kk_*: `RuntimeSequenceAssociation.swift` の全関数（rg で列挙）
- [ ] KSP-445: Sequence fold/scan を Kotlin 化（`fold(Indexed)`, `reduce(Right)(Indexed)(OrNull)`, `scan(Indexed)`, `runningFold/Reduce(Indexed)`, `sorted*`）
  - 削除 kk_*: `RuntimeSequenceFoldScan.swift` の全関数
- [ ] KSP-446: Sequence `*To` 宛先変種を Kotlin 化（`filterTo` 等 11 関数、`RuntimeSequenceBuilders.swift` 内 STDLIB-SEQ-021 群）
- [ ] KSP-447: sequence{}/iterator{} ビルダーを (c) 残留分類として確定する
  - coroutine 機構と不可分（`kk_sequence_builder_*`, `kk_iterator_builder_*` 11 関数）。`__kk_` 降格 + `docs/stdlib-pipeline.md` §9 の (c) 表へ記載のみ。Kotlin 化はしない

#### kotlin.ranges [M6 実行体]（前提: KSP-312）

- [ ] KSP-451: Range プロパティ・membership を完遂（`first`, `last`, `start`, `endInclusive/Exclusive`, `count`, `isEmpty`, `contains`, `sum`, `reversed` の Int/Long/Char 版）
  - 削除 kk_*: `kk_range_first`, `kk_range_last`, `kk_range_start`, `kk_range_end`, `kk_range_endExclusive`, `kk_range_count`, `kk_range_isEmpty`, `kk_range_contains`, `kk_range_sum`, `kk_range_reversed`, `kk_long_range_*` 同系, `kk_char_range_isEmpty`
- [ ] KSP-452: for-in の range 特例を `.iterator()` 経路へ統一する
  - 変更: `ExprLowerer+ControlFlowAndBlocks.swift` の range 直接特例を、KSP-312 で配線した Kotlin `iterator()`（インライン展開）に置換。性能退行は diff_kotlinc + 簡易ベンチで確認し、退行時はループ最適化パスの課題として報告
  - 削除 kk_*: `kk_range_iterator`, `kk_range_hasNext`, `kk_range_next`, `kk_long_range_iterator`
- [ ] KSP-453: IntRange HOF を Kotlin 化（`RuntimeRangeIntRangeHOF.swift` の約 30 関数: `toList`, `forEach`, `map*`, `filter*`, `reduce*`, `fold*`, `find*`, `first/last(OrNull)(_predicate)`, `any`, `all`, `none`, `chunked`, `windowed`, `take`, `drop`, `average`, `sorted`, `toIntArray`）
  - 実装方針: `Iterable<Int>` の汎用 HOF へ委譲する形で個別 kk_* を不要化
- [ ] KSP-454: LongRange/CharRange HOF を Kotlin 化（`RuntimeRangeLongRange.swift` の HOF 群 + `kk_char_range_toList/forEach/take/drop/sorted`）
- [ ] KSP-455: UInt/ULong Range を Kotlin 化（`RuntimeRangeUIntULongRange.swift` の全 HOF/プロパティ約 80 関数）
  - 前提: 符号なし型のジェネリクス/演算対応を着手時に確認。困難なら (b)→(c) 再分類を提案して中断
- [ ] KSP-456: progression 構築系を Kotlin 化（`step`, `downTo`, `until`, `*_progression_fromClosedRange`）
  - 削除 kk_*: `kk_op_step`, `kk_op_downTo`, `kk_op_rangeUntil`, `kk_int/long/uint/ulong/char_progression_fromClosedRange` ほか（`kk_op_rangeTo` は演算子コアのため残留可）
- [ ] KSP-457: range random 系を Kotlin 化（前提: KSP-466。`kk_range_random*`, `kk_long_range_random*`, `kk_char_range_random*`, `kk_uint/ulong_range_random*`, `kk_random_nextInt/nextLong_rangeObject`）

#### kotlin.comparisons [M5 実行体]（前提: KSP-309）

- [ ] KSP-461: Comparator 群を完遂する（`nullsFirst/Last` 各種, `reversed`, multi-selector `compareBy`×3, `compareValues(By)`×6, `CASE_INSENSITIVE_ORDER`, primitive selector 版）
  - 削除 kk_*: `RuntimeComparator.swift` の残存全関数（trampoline 含む 53 − KSP-309 分。`rg -o '@_cdecl\("kk_(comparator|compareValues|comparable)[a-zA-Z_]*"\)' Sources/Runtime` で列挙）。比較コア `kk_comparable_compareTo` のみ `__kk_` 降格可
- [ ] KSP-462: maxOf/minOf 全オーバーロードを Kotlin 化 [MIGRATION-COMP-002]（Comparable 版・プリミティブ版・vararg 版）
  - 対象確認: `rg -ln 'maxOf|minOf' Sources/CompilerCore/Sema/DataFlow` で登録スタブを特定してから着手

#### kotlin.random [M7 実行体]

- [ ] KSP-466: Random を Kotlin 化する（本家同様 XorWow 相当の決定的アルゴリズムを Kotlin 実装）
  - ブリッジ残留: 初期シード用エントロピー取得 `__kk_random_seed_entropy`（新設）のみ。`kk_random_nextInt/Long/UInt/ULong/Float/Double/Boolean/Bits/Bytes/UBytes` 系 30+ 関数（`RuntimeRandom.swift`）を Kotlin 実装で置換・削除
  - 注意: 乱数出力列が現行実装と変わる。`rg -l 'random' Scripts/diff_cases` のケースがシード固定の期待値に依存していないか先に確認し、依存があればケースを期待値非依存形へ修正
- [ ] KSP-467: SecureRandom / asJavaRandom 互換層を `__kk_` 降格する（`kk_secure_random_*` 4 関数, `kk_random_asKotlinRandom`, `kk_random_asJavaRandom`, `kk_random_create_seeded`, `kk_random_default`）

#### kotlin.time [M8 実行体]

- [ ] KSP-471: Duration を Kotlin 化する（構築 21+、`inWhole*` 7、述語 4、算術 6、`compareTo`、`absoluteValue`、`toString`/`toIsoString`/`parse*` 6、`toComponents` 4）
  - 注意: 死蔵 `Stdlib/kotlin/time/Duration.kt` を下敷きに `Sources/CompilerCore/Stdlib/kotlin/time/Duration.kt` として移設。インライン `kotlinTimeSource`（数値拡張プロパティ 21 個含む）を**同一 PR で**削除（KSP-503 と統合可）
  - 削除 kk_*: `RuntimeDuration.swift` の該当関数（rg で列挙、`kk_measureTime*`/`kk_timedvalue_*` を除く）/ diff: `duration_*.kt` 5 ケース（既存）
- [ ] KSP-472: Instant/Clock/measureTime のブリッジを確定する
  - ブリッジ残留（`__kk_` 降格）: `kk_instant_now`, `kk_clock_system_now`, `kk_clock_now`, `kk_measureTime`, `kk_measureTimedValue`（時刻源）
  - Kotlin 化: `kk_instant_epoch_seconds`, `kk_instant_nano_of_second`, `kk_instant_is_distant_past/future`, `kk_instant_plus/minus_duration`, `kk_instant_compare`, `kk_instant_until`, `kk_instant_elapsed`（now ブリッジ経由）, `kk_instant_from_epoch_millis`, `kk_timedvalue_*` 3 関数

#### kotlin.uuid [M12 実行体]

- [ ] KSP-476: Uuid を完遂する（KSP-310 で残った API + `ByteArray.uuid`/`putUuid` 拡張、`LEXICAL_ORDER`）
  - 削除 kk_*: `kk_byteArray_uuid`, `kk_byteArray_putUuid`, `kk_uuid_getUuid`, `kk_uuid_lexicalOrder`, `kk_uuid_nil` / 完了: `rg '"kk_uuid_' Sources/CompilerCore` 0 件 + G

### KSP-W5: 後始末（W3/W4 の対応タスク完了後）

- [ ] KSP-501: `BundledKotlinStdlib.kotlinCollectionsSource` を .kt 化する（`count`/`any`/`all`/`none`/`sumOf`/`maxByOrNull`/`minByOrNull` → `collections/ListAggregateHOF.kt` へ移設。live ツリーとの重複なしは 2026-07-01 に確認済み）
- [ ] KSP-502: `kotlinTextSource` を .kt 化する（`repeat`/`reversed`/`padStart`/`padEnd`/`encodeToByteArray`×3/`decodeToString`×4/`indent`×2 → `text/` 配下へ。**注意**: `trimIndent`/`trimMargin`/`prependIndent`/`replaceIndent`/`replaceIndentByMargin` は KSP-302 で処理済みのはず — 残っていれば重複させず統合）
- [ ] KSP-503: `kotlinSequencesSource`/`kotlinTimeSource` を .kt 化し、`BundledKotlinStdlib.swift` と `FrontendPhases.swift` の `residualSources` 注入を削除する
  - 完了: `rg 'BundledKotlinStdlib' Sources` 0 件 + G
- [ ] KSP-504: ルート `Stdlib/` 死蔵ツリー（35 ファイル）を整理する
  - 手順: (1) `Package.swift` の `resources: [.copy("Stdlib")]` が `Sources/CompilerCore/Stdlib` を指すこと（ルートではない）を確認 (2) 各 .kt を「対応 KSP タスクの下敷きに使う / 即削除」に分類（W3/W4 の該当タスクへ移設済みのものから削除） (3) `git rm -r Stdlib/`
  - 完了: ルート `Stdlib/` が存在しない + G
- [ ] KSP-505: `excludedBundledStdlibFiles` 機構を撤廃し、ファイル名を本家準拠へリネームする
  - 前提: W3 全完了。手順: (1) セットが空であることを確認して機構ごと削除 (2) `text/Strings.kt`, `collections/Collections.kt` 等 kotlin-stdlib 本家のファイル構成へ統合リネーム（`docs/stdlib-pipeline.md` §6） (3) U で golden 更新
- [ ] KSP-506: fiction audit を再実行し削減推移を記録する（= RF-STUB-007。`DUMP_SURFACE=1` → `docs/stdlib-fiction-audit.md` へ現在値と推移を追記）

## ターゲット外バックログ（本体非追跡）
#### JVM Atomic相互運用stub
- [ ] CLEANUP-STUB-024: `kk_java_atomic_int_asKotlinAtomic` stub削除（`HeaderHelpers+SyntheticAtomicStubs.swift`, `RuntimeAtomic.swift`実装も削除）
- [x] CLEANUP-STUB-028: `kk_java_atomic_int_array_asKotlinAtomicArray` stub削除（`HeaderHelpers+SyntheticAtomicStubs.swift`, `RuntimeAtomic.swift`実装も削除）
#### JS/Wasm/JVM stub登録呼び出し削除

## テスト改善タスク
- [x] TEST-SEQ-009: `kotlin.sequences` の `findLast` / `partition` に Runtime テストを追加する。`kk_sequence_findLast` / `kk_sequence_partition` は専用ランタイム実装があるのに `Tests/RuntimeTests/RuntimeSequenceTests*.swift` での参照が 0 件。カバー対象: 空シーケンス・単一要素・マッチなし（`findLast` は `null`）・全要素マッチ・`partition` の predicate による 2 分割（`Pair<List, List>`）。`count` は基本ケース（`testCountReturnsElementCount`）のみ存在のため、空シーケンスと `predicate` 版を補完する

## 公式ドキュメント整合性チェック（Kotlin docs parity）

## 仕様準拠監査（Spec Conformance Audit）

Kotlin 公式仕様 / stdlib ドキュメントを基準に挙動を照合し、差異を記録・修正する継続タスク。

### 方法論
- 公式に文書化された挙動を真とし、二層で検証する:
  1. **doc 由来ユニットテスト**（kotlinc 非依存・CI 強制）: 期待値を直接アサート。例: `Tests/RuntimeTests/RuntimeFloatingPointToStringTests.swift`。
  2. **kotlinc 比較 diff ケース**: `Scripts/diff_cases/num_*.kt` を `Scripts/diff_kotlinc.sh` で本物の kotlinc(2.3.10) と突き合わせる。
- 採番は `SPEC-NUM-{NUMBER}`。修正できない大規模/横断要因は再現 diff ケースを `// SKIP-DIFF` で残し追跡する（修正後にマーカーを外せば回帰テストになる）。

### 数値・プリミティブ型（第1バッチ）

## 全体リファクタリング計画（RF0–RF9）

> 調査日: 2026-06-10。実測: CompilerCore ~229k 行（うち Sema/DataFlow ~104k、合成スタブ約100ファイル/~9万行）、
> Runtime ~63k 行、Tests ~214k 行、`interner.resolve == "名前"` 特例 104 箇所（TypeCheck）、`"kk_` リテラル 6,738 箇所（CompilerCore）。
> 方針: (1) 削除予定コードは磨かない（リネーム・分割をしない） (2) 各タスクは独立 PR サイズ
> (3) 完了ゲートは既存の `swift_test.sh` / golden / `diff_kotlinc.sh` / jscpd を流用
> (4) M1–M17・CLEANUP-STUB-001〜084 とは重複させず、本計画はその「前提基盤」と「それ以外の負債」を扱う。

### Phase RF0: 計測・ガードレール（他フェーズの前提・即着手可）
- [ ] RF-GUARD-001: LoC メトリクススクリプト `Scripts/loc_report.sh` を追加する（ディレクトリ別行数 / `HeaderHelpers+Synthetic*` 合計行数 / `"kk_` リテラル数 / `interner.resolve == "..."` 数を TSV 出力）。ベースライン値を `docs/refactoring-metrics.md` に記録する
- [ ] RF-GUARD-002: `.jscpd.json` の `path` に `Tests/` を追加し重複率を再計測する（まず report-only ジョブで観測、閾値は実測後に設定。現状 Tests/ は完全に未監視）
- [x] RF-GUARD-003: SwiftLint の `file_length` / `type_body_length` を有効化し、既存違反は `.swiftlint.baseline.json` で凍結する（新規悪化のみ CI fail にするラチェット）
- [x] RF-GUARD-004: `RuntimeABIExternalLinkValidationTests` の検証範囲を調査し、「CompilerCore が emit しうる全 `kk_*` 名が `RuntimeABISpec` に宣言されている」ことの検証ギャップ一覧を作る（enforcing 化は RF-KIR-005）。調査結果: [`docs/runtime-abi-external-link-validation-gaps.md`](docs/runtime-abi-external-link-validation-gaps.md)
- [x] RF-GUARD-005: リファクタ PR の必須ゲート（全テスト + golden + `diff_kotlinc.sh` green、`loc_report.sh` の悪化なし）を `CLAUDE.md` に明文化する

### Phase RF1: プロセス資産の修復（依存なし・並列可）
- [ ] RF-HYG-001: TODO.md の重複タスク ID を解消する（`STDLIB-TEXT-FN-088〜108` ブロックに同一 ID が最大 7 回出現し `[x]`/`[ ]` が矛盾、`STDLIB-COMP-FN-030/032/034` 重複、`PARITY-NUM-001` ×2、`PARITY-SEMA-003` ×2 等）。実装の実態を確認して真の状態へ正規化する
- [ ] RF-HYG-002: TODO.md の構造破損を修復する（`#### kotlin.uuid 関数の実装` 見出し重複等）。修復後に ID 重複を検出する軽量チェック（`rg -o '[A-Z]+-[A-Z-]+-[0-9]+' TODO.md | sort | uniq -d`）を Scripts に追加する
- [ ] RF-HYG-003: MIGRATION-TEXT-004 / MIGRATION-TEXT-009 の完了状態を監査する（`Stdlib/*.kt` は現状コンパイラから一切読み込まれておらず、実態は Runtime ブリッジ整理 + 死蔵 .kt 併置。完了の定義を RF-STDLIB 系の新基準で再判定し注記する）
- [x] RF-HYG-004: Stdlib ソース配置を一本化する（ルート `Stdlib/kotlin/text/StringComparison.kt` と `Sources/CompilerCore/Stdlib/kotlin/text/StringSplitJoin.kt` の 2 系統を統合。推奨: `Bundle.module` で読める `Sources/CompilerCore/Stdlib/`。Swift ソース 0 件の `Stdlib` ターゲットと未使用 `resources: [.process("Stdlib")]` の Package.swift 設定もここで整理）
- [x] RF-HYG-005: `docs/ARCHITECTURE.md` を実態に同期する（モジュール構成に LSPServer / KSwiftLSPCLI / GoldenHarnessSupport / GoldenHarnessWorker / Stdlib / RuntimeTestsParallel を追加、「テストFW: XCTest」を「XCTest 主体 + Golden は Swift Testing」に修正、CI ジョブ表へ full-swift-tests / diff-regression-shards を反映）
- [ ] RF-HYG-006: `docs/spec.md` / `docs/debugging.md` の stale 記述を監査する（参照ファイルの実在チェックを含む）
- [ ] RF-HYG-007: `.vscode/launch.json` の git 追跡可否を決定する（不要なら gitignore へ）

### Phase RF2: Stdlib ソースパイプライン基盤（本計画のクリティカルパス）
> 背景: M1–M17 の前提となる「bundled .kt をコンパイルに含める機構」が未実装。`LoadSourcesPhase` は `ctx.options.inputs` のみ読み込む。
- [ ] RF-STDLIB-001: 設計メモ `docs/stdlib-pipeline.md` を作成する（読み込みフェーズ・合成スタブとの優先順位・インクリメンタルキャッシュ / golden への影響・コンパイル時間戦略。実装前に 1 PR でレビュー）→ 文書作成済み・レビュー待ち（2026-07-01）
- [x] RF-STDLIB-002: `LoadSourcesPhase` に bundled Stdlib ソース読み込みを実装する（`Bundle.module` 列挙 → `sourceManager` 登録、`-no-default-stdlib-sources` での opt-out、ユーザー入力との診断パス区別）
- [ ] RF-STDLIB-003: 宣言の優先規則を実装する（Stdlib ソース由来宣言が存在する場合、同シグネチャの合成スタブ登録をスキップ。二重定義は warning 診断で検知）→ KSP-001〜003 に細分化
- [ ] RF-STDLIB-004: E2E 縦切り第1弾: `StringComparison.kt` の `commonPrefixWith`/`commonSuffixWith` をパイプライン実配線し、対応する合成スタブ + TypeCheck フォールバック + runtime `@_cdecl` を同一 PR で削除する（以後の移行のテンプレート）→ KSP-201
- [ ] RF-STDLIB-005: E2E 縦切り第2弾: `StringSplitJoin.kt`（MIGRATION-TEXT-004 対象）を実配線し、`kk_string_split*` 系直接 dispatch を Kotlin 層経由に置換する → KSP-202
- [ ] RF-STDLIB-006: stdlib 常時コンパイルのオーバーヘッドを `PhaseTimer` で計測し、許容超過なら build 時 pre-parse キャッシュ（`IncrementalCompilationCache` 流用）を追加する → KSP-006/007
- [ ] RF-STDLIB-007: golden / `diff_kotlinc.sh` ハーネスが implicit stdlib ソース込みで決定的に動くよう正規化する（fileID 順序・診断ソートの安定性）→ KSP-004/005
- [ ] RF-STDLIB-008: M1–M17 の完了条件を「.kt 実配線 + 合成スタブ削除 + runtime 関数削除（または `__` ブリッジ降格）」に統一し、本ファイル M セクション冒頭の移行方針を更新する → KSP 共通テンプレート T に反映済み

### Phase RF3: 合成スタブ削減（RF2 完了後に本格化。(a) 群のみ即着手可）
> 背景: `HeaderHelpers+Synthetic*` 約100ファイル/~9万行。ボイラープレート率 60–70%。登録呼び出しは `registerSyntheticDelegateStubs` に 85+ 連鎖。
- [ ] RF-STUB-001: 全スタブファイルを「(a) JS/Wasm/JVM 系 → CLEANUP-STUB-001〜084 で削除」「(b) M1–M17 でソース移行」「(c) 真のコンパイラ組込（Any・プリミティブ等）として残留」に 3 分類した棚卸し表を `docs/stdlib-pipeline.md` に追加する
- [x] RF-STUB-002: (a) 群削除のリファレンス PR を 1 件実施する（CLEANUP-STUB-033/034 の登録呼び出し削除を起点に、スタブ → runtime 実装 → テスト → golden の削除手順を確立し、残りの CLEANUP-STUB を量産可能にする）
- [ ] RF-STUB-003: (c) 残留スタブ向けの宣言的登録 API を導入する（RuntimeABI の `StdlibSurfaceSpec` パターンを Sema 登録へ拡張し、~340 個の `registerXxxMember` 手書き関数をデータテーブル化）
- [ ] RF-STUB-004: `SyntheticNativeConcurrent*` 16 ファイル（1–2 シンボル/ファイル）を宣言テーブル 1–2 ファイルへ統合する
- [ ] RF-STUB-005: 紛らわしい残留群を統合する（`SyntheticCoroutineStubs` vs `SyntheticCoroutinesStubs` vs `SyntheticCoroutineHelpers`、`SyntheticIterableStubs` vs `SyntheticIterableMembers`。※(a) 削除予定群はリネーム・統合の対象外）
- [ ] RF-STUB-006: `registerSyntheticDelegateStubs`（85+ 逐次呼び出し）と `+SyntheticPhase_ExtendedStdlib` / `+SyntheticPhase_PlatformAndJS` の分割アーティファクトを (a)(b)(c) 分類に沿ったレジストリ構造へ再編する
- [ ] RF-STUB-007: stdlib fiction audit を再実行し（`DUMP_SURFACE=1`）、合成サーフェス 6888 シンボルの現在値と削減推移を `docs/stdlib-fiction-audit.md` に追記する（以後フェーズ完了ごとに更新）

### Phase RF4: 名前文字列ベース特殊処理の排除（Sema / KIR）
> 背景: TypeCheck に `interner.resolve(...) == "名前"` が 104 箇所、`CallLowerer+LegacyMemberLikeCalls.swift` は 4,055 行・`kk_` リテラル 601 個。
- [ ] RF-SEMA-001: TypeCheck の名前比較特例 104 箇所の台帳を作る（機能・対応スタブ・スタブ/ソース移行後に削除可能か、の 3 列）
- [ ] RF-SEMA-002: `markStdlibSpecialCallExpr` 系特例（repeat / measureTime* / Array コンストラクタ等）をシンボル登録時メタデータ（flags / annotation）駆動の共通機構へ置換し、2–3 例を移して実証する
- [ ] RF-SEMA-003: `CallTypeChecker+MemberCallInferenceRegularNoCandidateFallbacks.swift`（2,157 行・17 特例）を、宣言充実に合わせて特例単位で段階削除する
- [ ] RF-SEMA-004: `+CollectionMemberFallback` / `+MemberCallInferenceCollectionFlow`（計 ~5.5k 行）に散在するレシーバ判定述語（isArrayReceiver / isIterableReceiver / isMapReceiver 等）を単一の ReceiverClassifier へ抽出する
- [ ] RF-SEMA-005: `CallTypeChecker.swift`（3,896 行）の特例ブロックをレジストリ移行済み分から削除し 3,000 行未満にする（以降 RF-GUARD-003 のバジェットで維持）
- [x] RF-KIR-001: `CallLowerer+LegacyMemberLikeCalls.swift` の dispatch を `externalLinkName` / `MemberDispatchKey` ベースの表駆動へ移行する設計 + 第1弾（数値系）
- [ ] RF-KIR-002: 同 第2弾（String 系）を表駆動へ移行する
- [ ] RF-KIR-003: 同 第3弾（Collection 系）を移行し、ファイルを解体して "Legacy" の名称を消滅させる
- [x] RF-KIR-004: `kk_int` / `kk_long` / `kk_double` プレフィックス判定の重複ヘルパー（`CallLowerer.swift` と `+Operators.swift` 等で反復）を 1 箇所へ統合する
- [x] RF-KIR-005: RF-GUARD-004 の検証を enforcing に昇格する（`RuntimeABISpec` 未宣言の `kk_*` 名 emit を CI fail にする）

### Phase RF5: Lowering パス再編（RF3/RF4 の削減確定後、残存コードのみ）
- [ ] RF-LOWER-001: KIR + Lowering の TODO/FIXME 約 620 件を triage する（即修正 / タスク化 / 削除の 3 分類。件数を RF-GUARD-001 メトリクスへ組み込み）
- [ ] RF-LOWER-002: `CollectionLiteralLoweringPass`（31 ファイル・~12k 行）を責務分割する（リテラル構築 / VirtualCallRewrite / LookupTables を独立パス・レジストリへ。`+PreScan.swift:671` の単純名マッチによる stdlib 誤分類も解消）
- [ ] RF-LOWER-003: `CallLowerer+Operators` / `CallRewrite` / `VirtualCallRewrite` に跨る sequence plus/minus 重複ロジックを共通ヘルパーへ抽出する（`+Operators.swift:211` の既知 TODO）
- [ ] RF-LOWER-004: `InlineLoweringPass`（1,280 行）と `LambdaClosureConversionPass` の共有ヘルパーを抽出する（`InlineLoweringPass.swift:428` の既知 TODO）
- [x] RF-LOWER-005: `ABILoweringPass+NonThrowingCallees`（1,298 行）と boxing rules の責務境界を整理する
- [ ] RF-LOWER-006: `DataEnumSealedSynthesisPass+DataClassMethods`（1,268 行・TODO 33 件）を整理し、`.jscpd.json` の ignore 固定 3 ファイルを解消する

### Phase RF6: Runtime 縮小・ABI 整合（M タスク進行と連動）
- [ ] RF-RT-001: Range HOF 3 ファイル（Int / Long / UInt-ULong、~1.5k 行）の型別重複を Swift generics で統合する
- [ ] RF-RT-002: `kk_list_component1..5` 等の薄ラッパ族を統合・生成化する
- [x] RF-RT-003: `RuntimeStringStdlib.swift`（4,542 行・211 @_cdecl）を M1 の進行に合わせ「migrated 関数の削除 or `__` ブリッジ降格」で縮小する
- [ ] RF-RT-004: `RuntimeCollectionHOF`（3,183 行）と `RuntimeSequence`（3,867 行）の fold/reduce/filter/map 系共通化可能箇所を調査し統合する
- [x] RF-RT-005: Runtime の全 `@_cdecl` が `RuntimeABISpec` に宣言されていることの CI 検証を網羅化する（`validate_runtime_abi_links.sh` 拡張、RF-KIR-005 と対）

### Phase RF7: テスト資産再編
- [ ] RF-TEST-001: Codegen 統合テスト（`CodegenBackendIntegrationTests+*` 214 ファイル・ボイラープレート ~13k 行）向けの fixture 駆動ハーネスを設計し、1 領域を移行する実証 PR を出す（.kt + expected stdout ペア、`Scripts/diff_cases` と同形式）
- [ ] RF-TEST-002: fixture 化を領域単位で展開し、「新規 Codegen 実行テストは fixture 必須」のガイドラインを `docs/ARCHITECTURE.md` に追記する
- [ ] RF-TEST-003: `*SyntheticMemberLinkTests` 群（List 2,140 行 / Sequence 2,552 行 / String 1,696 行）は対応スタブの削除と同一 PR で削除するルールにする（リファクタ対象にしない）
- [ ] RF-TEST-004: `SemanticsAndUtilitiesRegressionTests.swift`（3,520 行）を責務別に分割する
- [ ] RF-TEST-005: GoldenCases/Sema 244 ケースのうち同型ケース（minof_* / maxof_* 等）をパラメタライズ統合する
- [ ] RF-TEST-006: XCTest / Swift Testing の使い分けポリシーを決定し `docs/ARCHITECTURE.md` に明記する（現状 Swift Testing は Golden 系 3 ファイルのみ）

### Phase RF8: 継続ガバナンス（ラチェット運用）
- [ ] RF-GOV-001: jscpd 閾値を重複削減の進行に合わせて段階的に引き下げる（現状 5.6%。ignore 3 ファイルの解消とセット）
- [ ] RF-GOV-002: `loc_report.sh` を CI artifact 化し、フェーズ別削減目標（例: Sema/DataFlow 104k → 30k、TypeCheck 特例 104 → 0、`CallLowerer+Legacy*` 4,055 行 → 0）の推移を追跡する
- [ ] RF-GOV-003: 各 RF フェーズの最終タスクとして `docs/ARCHITECTURE.md` の数値・ファイルリスト更新を必須化する
- [ ] RF-GOV-004: fiction audit / dead-code audit を四半期定期タスク化する（RF-STUB-007 の運用継続）

## 技術負債バックログ（コード監査 2026-06-12）

> 2026-06-12 のコード監査で検出した、RF0–RF8 と重複しない単発の負債タスク。記載の行番号・件数はすべて実コードで検証済み。
> 方針: (1) 各タスクは独立 PR サイズでフェーズ依存なく着手可（依存があるものは本文に明記） (2) 合成スタブ（`HeaderHelpers+Synthetic*`）のリネーム・分割は RF-STUB-001 の (a)(b)(c) 分類が先（「削除予定コードは磨かない」原則）のため本セクションでは扱わない (3) 完了ゲートは RF-GUARD-005 と同じ（全テスト + golden + `diff_kotlinc.sh` green）。

### Runtime 正確性（fatalError → catch 可能例外）
> kotlinc では catch 可能な例外になるべき箇所がプロセス即死する。SPEC-NUM-0002（ゼロ除算 SIGFPE）と同型の問題系。

- [ ] DEBT-RT-001: `Sources/Runtime/RuntimeStringBuilder.swift` の境界チェック 11 箇所の `fatalError("StringIndexOutOfBoundsException: ...")` を catch 可能な Kotlin 例外送出へ置換する。`sb.insert(99, "x")` 等のユーザーコード 1 行でプロセスが落ちる最も再現容易な箇所。`try/catch (e: IndexOutOfBoundsException)` の diff ケースで kotlinc と挙動一致を検証する
- [x] DEBT-RT-003: `Sources/Runtime/RuntimeRegex.swift` の正規表現フォールバック失敗時 `fatalError` 4 箇所（238 / 439 / 471 / 755 付近）を整理する。pattern はユーザー入力直通。静的フォールバック `(?!)` が失敗し得ないことの検証コメント化、または例外送出化
- [x] DEBT-RT-006: `Sources/Runtime/RuntimeRegex.swift:419` の NOTE コメントどおり、`kk_regex_create_with_option` / `kk_regex_create_with_options` が「effective pattern + try compile + fallback + box」ロジックをインライン重複している。コメント案の `createRegexBox(pattern:isLiteral:options:)` 共通ヘルパーへ抽出する

### Runtime コルーチン（コード内 CORO TODO の細分化）
- [ ] DEBT-CORO-002: `Sources/Runtime/RuntimeTypes.swift:490,708` — `RuntimeSequenceCoroutine` / `RuntimeMapCoroutine` の producer/consumer セマフォ ping-pong が GCD スレッド 2 本をイテレーション中ずっとブロック（コード内 TODO(CORO-004)）。yield() を suspend ポイントとしてモデル化する移行をこの 2 型から着手する
- [ ] DEBT-CORO-003: `Sources/Runtime/RuntimeCoroutineContext.swift:691` — `withContext` が continuation 移行途中でセマフォ fallback のまま。continuation ベースへ完了させる

### Sema 近似実装・既知クラッシュ
- [x] DEBT-SEMA-001: `Sources/CompilerCore/Sema/TypeCheck/Helpers+TypeArgsAndMemberLookup.swift:113-135` の型エイリアス use-site variance 検証が no-op（計算結果を `_ = (declaredVariance, argVariance)` で破棄、`declaredVariance` は三項演算子の両分岐とも `.invariant`）。宣言側 variance を参照した実検証を実装するか、no-op で正しい仕様根拠をコメントへ明記する
- [x] DEBT-SEMA-002: `Sources/CompilerCore/Sema/DataFlow/OpenFinalOverride.swift:809` 付近のジェネリック戻り値の共変 override チェックが「For now, implement basic checks」の保守的近似。完全な型引数置換ベースへ拡張する。先に現状すり抜ける不正 override ケースを golden 化してから着手する
- [x] DEBT-SEMA-003: `Sources/CompilerCore/Sema/DataFlow/OpenFinalOverride.swift:959` 付近のモジュール境界の可視性検証（internal override 等）が保守的近似のまま。モジュール FQN 比較ベースの検証を実装する
- [x] DEBT-SEMA-004: `Sources/CompilerCore/Sema/DataFlow/BodyAnalysis.swift:693` の `typeArgInnerType(.star)` が `fatalError("typeArgInnerType called on .star")` — star projection `<*>` を含む入力でコンパイラ自体がクラッシュしうる。診断付きの安全な経路へ変更し、`<*>` を含む回帰テストを追加する

### KIR / Lowering
- [ ] DEBT-KIR-001: `Sources/CompilerCore/KIR/CallLowerer+SafeMemberCalls.swift:1085-1094` で vtable dispatch が無効化され常に static dispatch へフォールバックしている（「TODO: Re-enable once kk_alloc-based object allocation is in place」）。ブロッカーとされた `kk_alloc` は `Sources/Runtime/RuntimeGC.swift:151` に実装済みのため、前提充足を監査して再有効化を検討する。再有効化時は `VirtualDispatchTests` へ該当経路のケースを追加する
- [x] DEBT-KIR-003: `Sources/CompilerCore/Lowering/ABILoweringPass+NonThrowingCallees.swift` の手書き約 1,300 行 Set リテラルを `RuntimeABISpec` 由来の導出へ置換する。`RuntimeABIFunctionSpec` に throwing 属性が無いため throwing 情報が二重管理になっている — spec へ `isThrowing` フィールドを追加し、既存手書きリストとの全件突き合わせ検証を経て自動導出へ移行する（RF-LOWER-005 の具体化、RF-KIR-005 / RF-RT-005 とも整合）

### RuntimeABISpec 本体の分割完遂
> 既に 33 ファイルへ +分割済みだが、本体 `RuntimeABISpec.swift`（3,629 行）に 19 個の `static let *Functions` が残存する。
- [x] DEBT-ABI-001: `operatorFunctions`（約 508 行）を `RuntimeABISpec+Operator.swift` へ移動する
- [x] DEBT-ABI-002: `bitwiseFunctions`（約 322 行）を `RuntimeABISpec+Bitwise.swift` へ移動する
- [x] DEBT-ABI-003: `exceptionFunctions`（約 329 行）を `RuntimeABISpec+Exception.swift` へ移動する
- [ ] DEBT-ABI-004: `delegateFunctions`（約 259 行）/ `boxingFunctions`（約 117 行）ほか残存 static let を + ファイルへ移動し、本体を spec コア型定義 + 集約プロパティのみへ縮小する

### テスト衛生
- [x] DEBT-TEST-002: `Tests/CompilerCoreTests/Lowering/LoweringPassRegressionTests.swift:548` と `LoweringABIAndPropertyRegressionTests.swift:6` に同一実装の `private func makeContext(...)` がコピー存在する。`Integration/TestSupport/Pipeline.swift` の `makeCompilationContext()` へ統一する
- [x] DEBT-TEST-003: `Tests/CompilerCoreTests/Sema/SemaCacheContextTests.swift:8` の `makeContextFromSourceWithCache()` を、`Pipeline.swift` の `makeContextFromSource()` へ `frontendFlags` 引数を追加して統合する
- [ ] DEBT-TEST-004: KIR / Lowering テスト群に散在する `SemaModule(...)` 直接構築（計 90 箇所超: `BuildKIRRegressionTests+ExpressionAndAdvancedScenarios` / `VirtualDispatchTests+InliningCoroutineAndDispatchResolution` / `RuntimeTypeCheckTokenTests` 等）を `makeSemaModule()` ヘルパー利用へ移行する（ファイル単位で分割実施可）
- [ ] DEBT-TEST-005: `Scripts/diff_cases` の `// SKIP-DIFF` / `// KSWIFTK_DIFF_IGNORE` 65 ケースを棚卸しし、各ケースへ対応タスク ID（SPEC-* / PARITY-* / DEBT-*）をコメント付与する。対応タスクが無い skip は新規起票する（skip 放置の防止。SPEC 方法論「修正後にマーカーを外せば回帰テストになる」の運用徹底）

### ドキュメント乖離
- [ ] DEBT-DOC-001: `CLAUDE.md` コーディング規約の「Swift 5.9, macOS 12+」が実態（`Package.swift` は `swift-tools-version: 6.2` / `swiftLanguageModes: [.v6]`）と乖離している。修正する
- [ ] DEBT-DOC-002: `docs/ARCHITECTURE.md` §4 の KIR テーブルへ未記載の実在ファイルを追記する（`CallSupportLowerer` / `ObjectLiteralLowerer` / `KIRLoweringContext` / `ConstantCollector` / `LateinitReadWrapping` / `KClassAnnotationRegistrationLowering` / `MutableCaptureCellHelpers` / `RuntimeTypeCheckToken` 等。RF-HYG-005 はモジュール構成・CI 表のみでファイルテーブルは未カバー）
- [x] DEBT-DOC-003: `docs/ARCHITECTURE.md` §10 の Lowering パス実行順序へ未記載の実在パスを実行順付きで追記する（`EnumEntriesLoweringPass` / `EnumNameAccessLoweringPass` / `FlowLoweringPass` / `IntegerNarrowingPass` / `JvmOverloadsLoweringPass` / `JvmStaticLoweringPass` / `TailrecLoweringPass` / `ValueClassUnboxingPass`）
- [ ] DEBT-DOC-004: `docs/ARCHITECTURE.md` の「CoroutineLoweringPass (+分割3ファイル)」を実態（`+Analysis` / `+CallRewriting` / `+Flow` / `+FlowInstructionRewrite` / `+LauncherSupport` / `+StateMachine` / `+Synthesis` の 7 分割・計 8 ファイル）へ修正する
## Dead Code 削除タスク（DEADCODE: 2026-06-12 監査）

> 監査方法: (1) 識別子の「宣言数 = 全出現数」（参照ゼロ）による Swift シンボル抽出、(2) Runtime の全 `@_cdecl` 2,839 件について CompilerCore の文字列リテラル / 補間・連結による動的生成（`"\(prefix)_suffix"` 型を含む）/ `StdlibSurfaceSpec` テーブル経由、の全 emit 経路を検証。RF-GOV-004 の dead-code audit 第 1 回に相当。
> 注意: `RuntimeABISpec`(+ABIParity) への登録は ABI 宣言・C ヘッダ生成・リンク検証のみで emit 経路ではない。各削除タスクでは spec/parity 宣言と ABI テストの該当エントリも併せて削除する。
> 検証で ALIVE と確定し**削除禁止**のもの: `kk_atomic_*` 全 32 件（`HeaderHelpers+SyntheticAtomicStubs.swift` の接尾辞補間で emit）、`kk_match_result_destructured_component1..9` / `kk_base64_*`（補間 emit）、`kk_long_range_forEach` / `kk_long_range_map`（`MemberRuntimeDispatch` 経由）、`kk_bits_to_*` / `kk_*_to_bits` / `kk_*_trampoline` / `kk_future_complete` / `kk_flow_stopped` / `kk_with_context_full` / `kk_is_cancellation_exception` / `kk_kclass_register_metadata_v2` / `kk_context_get_dispatcher`（Runtime 内部呼び出し）。`kk_pin_object` / `kk_pinned_get` / `kk_unpin_object` は STDLIB-CINTEROP-FN-009/042 が配線予定のため対象外。
> 完了ゲートは RF-GUARD-005 と同じ（全テスト + golden + `diff_kotlinc.sh` green）。

### CompilerCore / LSPServer / RuntimeABI: 参照ゼロの Swift シンボル

### テストのみ参照（fiction 棚卸し — 配線するか、テストごと削除するか）
- [ ] DEADCODE-013: テストのみ参照の Swift シンボル約 20 件を棚卸しする — `PhaseTimer.exportTSV` / `exportJSON`、`KotlinParser.canStartTypeArguments`、`KotlinLanguageVersion` / `CompilerVersion`（`CompilerTypes.swift`、製品コードから未使用）、`BlockScope` / `validateExpectActualLinks` / `setTypeParameterUpperBound` / `hasContractReturnsNotNull`（`SemanticsModels.swift`）、`smartCastTypeForWhenSubjectCase`、DataFlow の `invalidateVariable` / `narrowToNonNull`、`IncrementalCompilationCache.clearCache`、`SemaCacheContext.invalidateScope`、`FileFingerprint.mtimeUnchanged`、`DependencyGraph.clearFile`、`RuntimeMetadataCodec` / `compilerPluginMetadata`（`RuntimeMetadata.swift`）、`RuntimeReflectionMetadataDecoder`、`completeCancellationIfNeeded`（`RuntimeCoroutine.swift:962`）、`runtimeDetectMemoryLeak`、`RuntimeABIExterns.externDecl`。意図的シーム（`Driver.runForTesting` / `RuntimeABISpec.generateCHeader` / `GoldenHarnessAPI.loadCasesOrCrash` / `renderInSubprocess`）は対象外

### 未監査領域（フォローアップ）
- [ ] DEADCODE-014: 今回未監査の領域を同手法で監査する — Runtime の C コード（GC 等の .c/.h）、診断コード `KSWIFTK-*` の未発行コード、stored property / global 定数、Tests 内ヘルパ、`Scripts/diff_cases` の SKIP-DIFF ケースの実行可否。以降は RF-GOV-004 の四半期運用に乗せる

### Phase RF9: デッドコード削除（dead-code audit 2026-06-12 検出分）

> 検出手法・全インベントリ・再現コマンドは `docs/dead-code-audit.md` を参照。
> 注意: `RuntimeABISpec`（`+ABIParity` / `+RuntimeOnlyBridge`）への登録は exported シンボルの必須ミラーであり「使用」の証拠ではない。
> 削除時は Runtime 実装と spec エントリをセットで消し、孤立する private ヘルパー・Box 型も同時に削除する。

- [x] RF-DEAD-001: 完全到達不能の `kk_*` ランタイム関数 102 個を削除する（CompilerCore から静的にも動的（文字列補間 25 プレフィックス・`StdlibSurfaceSpec` 表駆動）にも emit されず、Tests・Runtime 内部・`Stdlib/*.kt` からの参照もゼロ）。内訳: SLF4J 互換ロギング 28 / リフレクション（`kk_kclass_*` / `kk_kconstructor_*` / `kk_kproperty_*` / `kk_callable_ref_*`）32 / coroutines・Flow 19 / 配列 HOF 取り残し 8 / java.time・JS Date ブリッジ 5 / HTTP 2 / その他（`kk_math_pi` / `kk_char_plus` 等）8。カテゴリ単位の分割 PR 推奨
- [x] RF-DEAD-004: dead-code 検出を `Scripts/dead_code_audit.sh` としてスクリプト化する（`docs/dead-code-audit.md` の再現コマンドを移植。動的補間プレフィックス・`StdlibSurfaceSpec` 表駆動経路・テスト参照の除外を含む。RF-GOV-004 の四半期 audit で再利用）
---

## コード共通化タスク（REFACT: 2026-06-28 調査）

> 調査方法: KIR 層・Lowering 層・Sema 層・テスト層を横断して重複パターンを抽出。
> 優先度は影響ファイル数と「新 primitive 型追加時の修正箇所数」で決定。
> 完了ゲートは全テスト + golden + `diff_kotlinc.sh` green。

### HIGH: 影響大（多数ファイル or バグ温床）

- [ ] REFACT-001: primitive boxing/unboxing の switch 表を一元化する — `kk_box_int` / `kk_unbox_*` 等のマッピングが `CallLowerer.swift`・`LambdaLowerer.swift`・`ABILoweringPass+BoxingRules.swift`・`CollectionLiteralLoweringPass+FactoryPredicates.swift`・`CollectionLiteralLoweringPass+CallRewriteIteratorBridge.swift` の 6 箇所に独立実装されている。`BoxingCalleeTable` のような共有構造体に集約し、新 primitive 型追加時の修正箇所を 1 箇所にする
- [ ] REFACT-002: `ensureSyntheticPackage` ウォークパスヘルパーを共通化する — `SyntheticPackageRegistration.swift` の正規実装 `ensureSyntheticPackageHierarchy` がバイト単位で `HeaderHelpers+SyntheticMathStubs.swift` と `HeaderHelpers+SyntheticRandomStubs.swift` にコピーされている。`HeaderHelpers+SyntheticTODOAndIOStubs.swift` のリーフ版も含め、全 3 箇所を正規実装の呼び出しに置き換える
- [ ] REFACT-003: synthetic 拡張関数の登録ボイラープレートを共通化する — symbol 定義 → パラメータループ → `setFunctionSignature` の一連の処理が `HeaderHelpers+SyntheticStringRegistrationHelpers.swift`・`+SyntheticSequenceRegistrationHelpers`・`+SyntheticMutableListStubs`・`+SyntheticMathStubs`・`+SyntheticPathStubs+SymbolRegistration` の 5 ファイルで 60〜90 行ずつ重複している。共有ファイルに `registerSyntheticFunctionStub(...)` フリー関数を定義して各ヘルパーから呼び出す
- [ ] REFACT-004: `KIRArena.appendTemporary(type:)` メソッドを追加する — `arena.appendExpr(.temporary(Int32(arena.expressions.count)), type:)` という 2 ステップのイディオムが 41 ファイル・約 249 箇所に散在している。`KIRArena` に `appendTemporary(type:) -> KIRExpression` を追加して ID 採番を一元化し、全呼び出し側を置き換える
- [ ] REFACT-005: `resolveClassTypeSymbol` ヘルパーを共通化する — `guard case let .classType(...) = sema.types.kind(of: sema.types.makeNonNullable(...))` という 3 行ガードが 61 ファイルに散在している。`func resolveClassTypeSymbol(_ type: TypeID, sema: SemaModule) -> (ClassType, Symbol)?` のような共有ヘルパーを定義して置き換える

### MEDIUM: 局所的だが改善余地あり

- [ ] REFACT-006: boxing callee 名の文字列リテラルを単一の正規ソースに集約する — `ABILoweringPass.swift`・`ABILoweringPass+NonThrowingPrimitive.swift`・`CollectionLiteralLoweringPass+LookupTables.swift`・`CallLowerer.swift` の 4 箇所に `kk_box_*` / `kk_unbox_*` の interned 名リストが個別定義されている。`ABILoweringPass` の静的セットを正規ソースにして他の箇所はそれを参照する
- [ ] REFACT-007: `assertKotlinCompilesToKIR` と `assertKotlinSourcesToKIR` の重複ボディを共通ヘルパーに抽出する — `CompilationTestHelpers.swift` 内の 2 関数が `withTemporaryFile` vs `withTemporaryFiles` の違いだけで約 35 行同一の本体を持つ。`inputs: [String]` を受け取るプライベートヘルパーに共通部分を抽出する
- [ ] REFACT-008: テストの `module.arena.declarations.compactMap { guard case .function ... }` を共通ヘルパーに切り出す — 20+ テストファイルが `findAllKIRFunctions(in:)` 相当の処理をインラインで実装している。既存の `findKIRFunction(named:in:interner:)` と並置する形でテスト共有ファイルに追加し、重複する約 64 箇所を置き換える
- [ ] REFACT-009: boxing/unboxing call を emit する 3 行パターンを共通ヘルパーに抽出する — `appendExpr` + `instructions.append(.call(symbol: nil, canThrow: false, ...))` の組み合わせが `CallLowerer.swift`・`LambdaLowerer.swift`・`ABILoweringPass+BoxingRules.swift`・`CollectionLiteralLoweringPass+FactoryPredicates.swift` 等 12 箇所以上に重複している。`emitNonThrowingCall(callee:arg:resultType:arena:into:)` のようなヘルパーに集約する

### LOW: 軽微な冗長

- [ ] REFACT-010: `BuildASTPhase+TypeParsing.swift` の `isTypeLikeNameToken` 転送ラッパーを削除する — 本体が `TypeRefParserCore.isTypeLikeNameToken(kind)` 1 行の転送のみで、`TypeRefParserCore` の静的メソッドを直接呼ぶよう呼び出し元を書き換えて本ファイルのラッパーを削除する
