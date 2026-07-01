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
- [ ] STDLIB-TEXT-FN-048: `reduceIndexedOrNull` 関数の実装

### Phase 4: リフレクション・数値・テキスト・その他 stdlib

#### kotlin.comparisons 関数の実装
- [x] STDLIB-COMP-FN-015: `maxOf` 関数の実装（Float版、3引数）
- [ ] STDLIB-COMP-FN-040: `minOf` 関数の実装（Float版、vararg）
- [ ] STDLIB-COMP-FN-044: `minOf` 関数の実装（Long版、2引数）
- [ ] STDLIB-COMP-FN-046: `minOf` 関数の実装（Long版、vararg）

#### kotlin.random 型の実装

#### kotlin.random 関数の実装

- [~] STDLIB-CORO-001: `kotlin.coroutines.intrinsics` / cancellation — 主要部分実装済み（`suspendCoroutineUninterceptedOrReturn`, `intercepted`, `CancellationException`）。残課題は別チケットへ分割。

### Phase 5: 非スコープ/高度領域
- [ ] STDLIB-JS-COLLECTIONS-FN-005: `JsReadonlySet<E>.toMutableSet()` を追加する
- [ ] STDLIB-CINTEROP-FN-016: `CPointer<T>.set(index, value)` を追加する
- [x] STDLIB-CINTEROP-FN-026: `ULongArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-029: `ByteArray.toKString()` を追加する
- [x] STDLIB-CINTEROP-FN-035: `CPointer<UShortVar>.toKStringFromUtf16()` を追加する
- [x] STDLIB-CINTEROP-FN-034: `CPointer<ShortVar>.toKStringFromUtf16()` を追加する
- [x] STDLIB-CINTEROP-FN-018: `ByteArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-024: `UByteArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-025: `UIntArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-028: `List<CPointer<T>?>.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-025: `UIntArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-032: `CPointer<UShortVar>.toKString()` を追加する
- [ ] STDLIB-CINTEROP-FN-041: `CValue<T>.useContents(block)` を追加する
- [ ] STDLIB-CINTEROP-FN-042: `T.usePinned(block)` を追加する
- [x] STDLIB-CINTEROP-FN-045: `CValue<T>.write(location)` を追加する
- [x] STDLIB-CINTEROP-FN-044: `vectorOf(Int, Int, Int, Int)` の公式 annotation/signature を既存 stub と整合させる
- [x] STDLIB-CINTEROP-FN-046: `writeBits(ptr, offset, size, value)` を追加する
- [x] STDLIB-CINTEROP-FN-047: `zeroValue<T>()` を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-001: `kotlinx.cinterop.internal.CCall` annotation を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-004: `kotlinx.cinterop.internal.CGlobalAccess` annotation を追加する
- [x] STDLIB-DOM-TYPE-001: `org.w3c.dom.ItemArrayLike<T>` external interface を追加する
- [ ] STDLIB-JVM-166: Java プレビュー機能の実装
- [ ] STDLIB-REFL-175: アノテーション処理高度機能実装

## Kotlin Stdlib Source Migration（Stdlib/ 層への移行）

PR #3754 で導入した `Stdlib/` ディレクトリへの移行パターン（Kotlin ソースで公開 API を定義し、ネイティブ操作は `kswiftk.internal.*` ブリッジに委譲）を残りの stdlib 領域にも適用する。各タスクは対応する Runtime Swift ファイルのロジックを `Stdlib/*.kt` へ移し、コンパイラの call dispatch を新しい flat/source API 経路に接続する作業を含む。

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

- [ ] MIGRATION-RANGE-001: Range/Progression クラス API を Kotlin source に移行する（`IntRange`, `LongRange`, `CharRange`, `IntProgression`, `LongProgression`, `CharProgression` の iterator/contains/isEmpty）
- [x] MIGRATION-RANGE-002: Range HOF を Kotlin source に移行する（`forEach`, `map`, `filter`, `toList`, `count`）— IntRange/IntProgression/LongRange/LongProgression/CharRange/CharProgression 対応。`first`/`last`/`step`/`reversed` は既存 synthetic stub で完結（純 Kotlin 化には新規ネイティブブリッジが必要で挙動変化がないため対象外）。`count(predicate)` は Range member fallback（`CallTypeChecker+RangeMemberFallback.swift`）の arity allow-list が0引数のみ許可し呼び出し不能なため対象外
- [ ] MIGRATION-RANGE-003: Range ユーティリティを Kotlin source に移行する（`coerceIn`, `coerceAtLeast`, `coerceAtMost`, `until`, `downTo`）

### Phase M7: kotlin.random
> 移行元: `Sources/Runtime/RuntimeRandom.swift` (38 @_cdecl)
> 移行先: `Stdlib/kotlin/random/Random.kt`


### Phase M8: kotlin.time / Duration
> 移行元: `Sources/Runtime/RuntimeDuration.swift` (61 @_cdecl)
> 移行先: `Stdlib/kotlin/time/Duration.kt`

- [ ] MIGRATION-TIME-001: `Duration` 算術・変換を Kotlin source に移行する（`plus`, `minus`, `times`, `div`, `unaryMinus`, `absoluteValue`, `isPositive`, `isNegative`, `isInfinite`）

### Phase M9: kotlin.io File I/O
> 移行元: `Sources/Runtime/RuntimeFileIO.swift` (144 @_cdecl)
> 移行先: `Stdlib/kotlin/io/`


### Phase M10: kotlin.io.encoding
> 移行元: `Sources/Runtime/RuntimeBase64.swift` (26), `RuntimeHexFormat.swift` (18)
> 移行先: `Stdlib/kotlin/io/encoding/`


### Phase M11: kotlin.text Regex
> 移行元: `Sources/Runtime/RuntimeRegex.swift` (44 @_cdecl)
> 移行先: `Stdlib/kotlin/text/Regex.kt`


### Phase M12: kotlin.uuid
> 移行元: `Sources/Runtime/RuntimeUuid.swift` (24 @_cdecl)
> 移行先: `Stdlib/kotlin/uuid/Uuid.kt`

- [ ] MIGRATION-UUID-001: `Uuid` クラス API を Kotlin source に移行する（`Uuid.random`, `Uuid.parse`, `toString`, `toLongs`, `toByteArray`）

### Phase M13: kotlin (Result)
> 移行元: `Sources/Runtime/RuntimeResult.swift` (16 @_cdecl)
> 移行先: `Stdlib/kotlin/Result.kt`

- [ ] MIGRATION-RESULT-001: `Result` クラスと `runCatching` を Kotlin source に移行する（`isSuccess`, `isFailure`, `getOrNull`, `getOrDefault`, `getOrElse`, `getOrThrow`, `map`, `fold`, `onSuccess`, `onFailure`）

## ターゲット外バックログ（本体非追跡）
#### JVM Atomic相互運用stub
- [ ] CLEANUP-STUB-024: `kk_java_atomic_int_asKotlinAtomic` stub削除（`HeaderHelpers+SyntheticAtomicStubs.swift`, `RuntimeAtomic.swift`実装も削除）
- [x] CLEANUP-STUB-028: `kk_java_atomic_int_array_asKotlinAtomicArray` stub削除（`HeaderHelpers+SyntheticAtomicStubs.swift`, `RuntimeAtomic.swift`実装も削除）
#### JS/Wasm/JVM stub登録呼び出し削除
- [x] CLEANUP-STUB-033: `HeaderHelpers+SyntheticPhase_PlatformAndJS.swift`の全呼び出し削除
- [x] CLEANUP-STUB-034: `HeaderHelpers+SyntheticPhase_ExtendedStdlib.swift`のJS/Wasm/JVM関連呼び出し削除
#### その他JS固有stub（ファイル単位）
- [ ] CLEANUP-STUB-035: JS Console stub削除（`HeaderHelpers+SyntheticJsConsoleStubs.swift`）
- [ ] CLEANUP-STUB-036: JS Eval stub削除（`HeaderHelpers+SyntheticJsEvalStubs.swift`）
- [ ] CLEANUP-STUB-037: JS Json stub削除（`HeaderHelpers+SyntheticJsJsonStubs.swift`）
- [ ] CLEANUP-STUB-040: JS ParseIntRadix stub削除（`HeaderHelpers+SyntheticJsParseIntRadixStubs.swift`）
- [ ] CLEANUP-STUB-041: JS ParseFloat stub削除（`HeaderHelpers+SyntheticJsParseFloatStubs.swift`）
- [ ] CLEANUP-STUB-050: JS RegExpMatch stub削除（`HeaderHelpers+SyntheticJsRegExpMatchStubs.swift`）
- [ ] CLEANUP-STUB-051: JS Static stub削除（`HeaderHelpers+SyntheticJsStaticStubs.swift`）
- [ ] CLEANUP-STUB-052: JS ExternalArgument stub削除（`HeaderHelpers+SyntheticJsExternalArgumentStubs.swift`）
- [ ] CLEANUP-STUB-053: JS ExternalInheritorsOnly stub削除（`HeaderHelpers+SyntheticJsExternalInheritorsOnlyStubs.swift`）
- [ ] CLEANUP-STUB-054: JS DefinedExternally stub削除（`HeaderHelpers+SyntheticJsDefinedExternallyStubs.swift`）
- [ ] CLEANUP-STUB-055: JS String stub削除（`HeaderHelpers+SyntheticJsStringStubs.swift`）
- [x] CLEANUP-STUB-056: JS StringInterop stub削除（`HeaderHelpers+SyntheticJsStringInteropStubs.swift`）
- [x] CLEANUP-STUB-057: JS Qualifier stub削除（`HeaderHelpers+SyntheticJsQualifierStubs.swift`）
- [ ] CLEANUP-STUB-060: JS ReferenceInterop stub削除（`HeaderHelpers+SyntheticJsReferenceInteropStubs.swift`）
- [ ] CLEANUP-STUB-063: JS PrimitiveWrappers stub削除（`HeaderHelpers+SyntheticJsPrimitiveWrappers.swift`）
- [x] CLEANUP-STUB-064: JS CollectionsArray stub削除（`HeaderHelpers+SyntheticJsCollectionsArrayStubs.swift`）
- [ ] CLEANUP-STUB-065: JS CollectionsMap stub削除（`HeaderHelpers+SyntheticJsCollectionsMapStubs.swift`）
- [ ] CLEANUP-STUB-066: JS CollectionsSet stub削除（`HeaderHelpers+SyntheticJsCollectionsSetStubs.swift`）
- [x] CLEANUP-STUB-067: JS CollectionsReadonlyArray stub削除（`HeaderHelpers+SyntheticJsCollectionsReadonlyArrayStubs.swift`）
- [ ] CLEANUP-STUB-066: JS CollectionsSet stub削除（`HeaderHelpers+SyntheticJsCollectionsSetStubs.swift`）
- [x] CLEANUP-STUB-068: JS CollectionsReadonlySet stub削除（`HeaderHelpers+SyntheticJsCollectionsReadonlySetToMutableSetStubs.swift`）
- [x] CLEANUP-STUB-069: JS CollectionsReadonlyMap stub削除（`HeaderHelpers+SyntheticJsCollectionsReadonlyMapToMapStubs.swift`）
- [ ] CLEANUP-STUB-072: JS Fun stub削除（`HeaderHelpers+SyntheticJsFunStubs.swift`）
- [x] CLEANUP-STUB-071: JS Any stub削除（`HeaderHelpers+SyntheticJsAnyStubs.swift`）
- [ ] CLEANUP-STUB-073: JS Export stub削除（`HeaderHelpers+SyntheticJsExportStubs.swift`）
- [ ] CLEANUP-STUB-077: JS Boolean stub削除（`HeaderHelpers+SyntheticJsBooleanStubs.swift`）
- [x] CLEANUP-STUB-079: JS Reference stub削除（`HeaderHelpers+SyntheticJsReferenceStubs.swift`）
- [ ] CLEANUP-STUB-078: JS Number stub削除（`HeaderHelpers+SyntheticJsNumberStubs.swift`）
- [ ] CLEANUP-STUB-080: JS RegExp stub削除（`HeaderHelpers+SyntheticJsRegExpStubs.swift`）
- [x] CLEANUP-STUB-081: JS Stubs（メイン）削除（`HeaderHelpers+SyntheticJsStubs.swift`）
- [ ] CLEANUP-STUB-084: JVM Metaprog stub削除（`HeaderHelpers+SyntheticMetaprogStubs.swift`）
- [ ] CLEANUP-STUB-083: JVM Reflect stub削除（`HeaderHelpers+SyntheticJvmReflectStubs.swift`）
- [ ] CLEANUP-STUB-095: `RuntimeABISpec.swift` / `RuntimeABISpec+BridgeCoverage.swift` の `kk_js_*` spec 登録削除（`kk_js_array_*` 6 / `kk_js_map_*` 2 / `kk_js_set_*` 2 / `kk_js_bigint_toLong` / `kk_js_boolean_toBoolean` / `kk_js_number_*` 2 / `kk_js_reference_get` の計 15 シンボル。各 stub 削除タスクの完了に合わせて段階的に外す）
- JDBC / DB コネクション・トランザクション・プール
- JVM 風ロギングフレームワーク互換
- `kotlin.jvm` / `kotlin.js` / `kotlin.wasm*` / `java.nio.file` 系・`kotlin.streams`
- kotlinx-metadata / コンパイラプラグイン API / KSP / KAPT
- kotlinx.coroutines の Flow 拡張（SharedFlow、高度演算子）
- JVM `java.time` / JS `Date` との相互運用
- `Runtime.getRuntime()` 系メモリ API（JVM モデル）
- HTTP・汎用シリアライゼーション
- `java.text` 前提の日時・数値フォーマット

## テスト改善タスク
- [x] TEST-SEQ-009: `kotlin.sequences` の `findLast` / `partition` に Runtime テストを追加する。`kk_sequence_findLast` / `kk_sequence_partition` は専用ランタイム実装があるのに `Tests/RuntimeTests/RuntimeSequenceTests*.swift` での参照が 0 件。カバー対象: 空シーケンス・単一要素・マッチなし（`findLast` は `null`）・全要素マッチ・`partition` の predicate による 2 分割（`Pair<List, List>`）。`count` は基本ケース（`testCountReturnsElementCount`）のみ存在のため、空シーケンスと `predicate` 版を補完する

## 公式ドキュメント整合性チェック（Kotlin docs parity）

Kotlin 公式 stdlib ドキュメントと実行時挙動を突き合わせて確認した結果を順次記録する。`[x]` は本リポジトリで修正済み、`[ ]` は未対応の残課題。検証は Swift Foundation の `CharacterSet` / `Unicode.Scalar.Properties` の実挙動を実機で確認した上で判断している。

### kotlin.text Char（2026-05-31 検証）

## Kotlin 挙動 parity（kotlinc 2.3.10 比較で発見した差分）

> `Scripts/diff_kotlinc.sh` を実 kotlinc 2.3.10（Swift 6.2 + LLVM 18）で実行して検出。`// KSWIFTK_DIFF_IGNORE` ケースは `--force-run-skipped` で再現可能。

- [x] PARITY-NUM-001: Int/Long/UInt の 32/64bit オーバーフロー・シフトが未実装（**重大・アーキテクチャ**）。native backend が全整数を i64 で表現し、Int(32bit) の演算結果を切り詰めず、シフト量もマスクしない（Int は `& 31`、Long は `& 63`）。
  - 症状: `Int.MAX_VALUE + 1` → `2147483648`（正 `-2147483648`）、`100000 * 100000` → `10000000000`（正 `1410065408`）、`1 shl 32` → `4294967296`（正 `1`）、`1 shl 31` → `2147483648`（正 `-2147483648`）、`1 shl -1` → `null`（範囲外シフトは LLVM 上 UB）、`UInt.MAX_VALUE + 1u` → `4294967296`（正 `0`）、`65601.toChar().code` → `65601`（正 `65`）。
  - 原因: `Sources/CompilerCore/Codegen/NativeEmitter+EmissionConstants.swift`（`kk_op_add`/`mul`/`shl`/`shr`/`ushr` 等が i64 のまま）と `NativeEmitter+FunctionEmission.swift` の `.binary` 経路。型(Int/Long)は KIR `exprTypes` にあるが emitter が TypeSystem を持たないため、型別 callee の分割か KIR 段での truncation/mask 挿入が必要（定数畳み込み経路も同様に未対応）。Byte/Short/Char/unsigned 縮約にも波及。
  - 再現: `Scripts/diff_cases/{integer_overflow_wraparound,shift_amount_masking,unsigned_arithmetic_overflow,int_to_char_truncation}.kt`。

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
- [ ] RF-GUARD-003: SwiftLint の `file_length` / `type_body_length` を有効化し、既存違反は `.swiftlint.baseline.json` で凍結する（新規悪化のみ CI fail にするラチェット）
- [ ] RF-GUARD-004: `RuntimeABIExternalLinkValidationTests` の検証範囲を調査し、「CompilerCore が emit しうる全 `kk_*` 名が `RuntimeABISpec` に宣言されている」ことの検証ギャップ一覧を作る（enforcing 化は RF-KIR-005）
- [ ] RF-GUARD-005: リファクタ PR の必須ゲート（全テスト + golden + `diff_kotlinc.sh` green、`loc_report.sh` の悪化なし）を `CLAUDE.md` に明文化する

### Phase RF1: プロセス資産の修復（依存なし・並列可）
- [ ] RF-HYG-001: TODO.md の重複タスク ID を解消する（`STDLIB-TEXT-FN-088〜108` ブロックに同一 ID が最大 7 回出現し `[x]`/`[ ]` が矛盾、`STDLIB-COMP-FN-030/032/034` 重複、`PARITY-NUM-001` ×2、`PARITY-SEMA-003` ×2 等）。実装の実態を確認して真の状態へ正規化する
- [ ] RF-HYG-002: TODO.md の構造破損を修復する（`#### kotlin.uuid 関数の実装` 見出し重複等）。修復後に ID 重複を検出する軽量チェック（`rg -o '[A-Z]+-[A-Z-]+-[0-9]+' TODO.md | sort | uniq -d`）を Scripts に追加する
- [ ] RF-HYG-003: MIGRATION-TEXT-004 / MIGRATION-TEXT-009 の完了状態を監査する（`Stdlib/*.kt` は現状コンパイラから一切読み込まれておらず、実態は Runtime ブリッジ整理 + 死蔵 .kt 併置。完了の定義を RF-STDLIB 系の新基準で再判定し注記する）
- [ ] RF-HYG-004: Stdlib ソース配置を一本化する（ルート `Stdlib/kotlin/text/StringComparison.kt` と `Sources/CompilerCore/Stdlib/kotlin/text/StringSplitJoin.kt` の 2 系統を統合。推奨: `Bundle.module` で読める `Sources/CompilerCore/Stdlib/`。Swift ソース 0 件の `Stdlib` ターゲットと未使用 `resources: [.process("Stdlib")]` の Package.swift 設定もここで整理）
- [ ] RF-HYG-005: `docs/ARCHITECTURE.md` を実態に同期する（モジュール構成に LSPServer / KSwiftLSPCLI / GoldenHarnessSupport / GoldenHarnessWorker / Stdlib / RuntimeTestsParallel を追加、「テストFW: XCTest」を「XCTest 主体 + Golden は Swift Testing」に修正、CI ジョブ表へ full-swift-tests / diff-regression-shards を反映）
- [ ] RF-HYG-006: `docs/spec.md` / `docs/debugging.md` の stale 記述を監査する（参照ファイルの実在チェックを含む）
- [ ] RF-HYG-007: `.vscode/launch.json` の git 追跡可否を決定する（不要なら gitignore へ）

### Phase RF2: Stdlib ソースパイプライン基盤（本計画のクリティカルパス）
> 背景: M1–M17 の前提となる「bundled .kt をコンパイルに含める機構」が未実装。`LoadSourcesPhase` は `ctx.options.inputs` のみ読み込む。
- [ ] RF-STDLIB-001: 設計メモ `docs/stdlib-pipeline.md` を作成する（読み込みフェーズ・合成スタブとの優先順位・インクリメンタルキャッシュ / golden への影響・コンパイル時間戦略。実装前に 1 PR でレビュー）
- [ ] RF-STDLIB-002: `LoadSourcesPhase` に bundled Stdlib ソース読み込みを実装する（`Bundle.module` 列挙 → `sourceManager` 登録、`-no-default-stdlib-sources` での opt-out、ユーザー入力との診断パス区別）
- [ ] RF-STDLIB-003: 宣言の優先規則を実装する（Stdlib ソース由来宣言が存在する場合、同シグネチャの合成スタブ登録をスキップ。二重定義は warning 診断で検知）
- [ ] RF-STDLIB-004: E2E 縦切り第1弾: `StringComparison.kt` の `commonPrefixWith`/`commonSuffixWith` をパイプライン実配線し、対応する合成スタブ + TypeCheck フォールバック + runtime `@_cdecl` を同一 PR で削除する（以後の移行のテンプレート）
- [ ] RF-STDLIB-005: E2E 縦切り第2弾: `StringSplitJoin.kt`（MIGRATION-TEXT-004 対象）を実配線し、`kk_string_split*` 系直接 dispatch を Kotlin 層経由に置換する
- [ ] RF-STDLIB-006: stdlib 常時コンパイルのオーバーヘッドを `PhaseTimer` で計測し、許容超過なら build 時 pre-parse キャッシュ（`IncrementalCompilationCache` 流用）を追加する
- [ ] RF-STDLIB-007: golden / `diff_kotlinc.sh` ハーネスが implicit stdlib ソース込みで決定的に動くよう正規化する（fileID 順序・診断ソートの安定性）
- [ ] RF-STDLIB-008: M1–M17 の完了条件を「.kt 実配線 + 合成スタブ削除 + runtime 関数削除（または `__` ブリッジ降格）」に統一し、本ファイル M セクション冒頭の移行方針を更新する

### Phase RF3: 合成スタブ削減（RF2 完了後に本格化。(a) 群のみ即着手可）
> 背景: `HeaderHelpers+Synthetic*` 約100ファイル/~9万行。ボイラープレート率 60–70%。登録呼び出しは `registerSyntheticDelegateStubs` に 85+ 連鎖。
- [ ] RF-STUB-001: 全スタブファイルを「(a) JS/Wasm/JVM 系 → CLEANUP-STUB-001〜084 で削除」「(b) M1–M17 でソース移行」「(c) 真のコンパイラ組込（Any・プリミティブ等）として残留」に 3 分類した棚卸し表を `docs/stdlib-pipeline.md` に追加する
- [ ] RF-STUB-002: (a) 群削除のリファレンス PR を 1 件実施する（CLEANUP-STUB-033/034 の登録呼び出し削除を起点に、スタブ → runtime 実装 → テスト → golden の削除手順を確立し、残りの CLEANUP-STUB を量産可能にする）
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
- [ ] RF-KIR-001: `CallLowerer+LegacyMemberLikeCalls.swift` の dispatch を `externalLinkName` / `MemberDispatchKey` ベースの表駆動へ移行する設計 + 第1弾（数値系）
- [ ] RF-KIR-002: 同 第2弾（String 系）を表駆動へ移行する
- [ ] RF-KIR-003: 同 第3弾（Collection 系）を移行し、ファイルを解体して "Legacy" の名称を消滅させる
- [ ] RF-KIR-004: `kk_int` / `kk_long` / `kk_double` プレフィックス判定の重複ヘルパー（`CallLowerer.swift` と `+Operators.swift` 等で反復）を 1 箇所へ統合する
- [ ] RF-KIR-005: RF-GUARD-004 の検証を enforcing に昇格する（`RuntimeABISpec` 未宣言の `kk_*` 名 emit を CI fail にする）

### Phase RF5: Lowering パス再編（RF3/RF4 の削減確定後、残存コードのみ）
- [ ] RF-LOWER-001: KIR + Lowering の TODO/FIXME 約 620 件を triage する（即修正 / タスク化 / 削除の 3 分類。件数を RF-GUARD-001 メトリクスへ組み込み）
- [ ] RF-LOWER-002: `CollectionLiteralLoweringPass`（31 ファイル・~12k 行）を責務分割する（リテラル構築 / VirtualCallRewrite / LookupTables を独立パス・レジストリへ。`+PreScan.swift:671` の単純名マッチによる stdlib 誤分類も解消）
- [ ] RF-LOWER-003: `CallLowerer+Operators` / `CallRewrite` / `VirtualCallRewrite` に跨る sequence plus/minus 重複ロジックを共通ヘルパーへ抽出する（`+Operators.swift:211` の既知 TODO）
- [ ] RF-LOWER-004: `InlineLoweringPass`（1,280 行）と `LambdaClosureConversionPass` の共有ヘルパーを抽出する（`InlineLoweringPass.swift:428` の既知 TODO）
- [ ] RF-LOWER-005: `ABILoweringPass+NonThrowingCallees`（1,298 行）と boxing rules の責務境界を整理する
- [ ] RF-LOWER-006: `DataEnumSealedSynthesisPass+DataClassMethods`（1,268 行・TODO 33 件）を整理し、`.jscpd.json` の ignore 固定 3 ファイルを解消する

### Phase RF6: Runtime 縮小・ABI 整合（M タスク進行と連動）
- [ ] RF-RT-001: Range HOF 3 ファイル（Int / Long / UInt-ULong、~1.5k 行）の型別重複を Swift generics で統合する
- [ ] RF-RT-002: `kk_list_component1..5` 等の薄ラッパ族を統合・生成化する
- [ ] RF-RT-003: `RuntimeStringStdlib.swift`（4,542 行・211 @_cdecl）を M1 の進行に合わせ「migrated 関数の削除 or `__` ブリッジ降格」で縮小する
- [ ] RF-RT-004: `RuntimeCollectionHOF`（3,183 行）と `RuntimeSequence`（3,867 行）の fold/reduce/filter/map 系共通化可能箇所を調査し統合する
- [ ] RF-RT-005: Runtime の全 `@_cdecl` が `RuntimeABISpec` に宣言されていることの CI 検証を網羅化する（`validate_runtime_abi_links.sh` 拡張、RF-KIR-005 と対）

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
- [ ] DEBT-RT-003: `Sources/Runtime/RuntimeRegex.swift` の正規表現フォールバック失敗時 `fatalError` 4 箇所（238 / 439 / 471 / 755 付近）を整理する。pattern はユーザー入力直通。静的フォールバック `(?!)` が失敗し得ないことの検証コメント化、または例外送出化
- [x] DEBT-RT-006: `Sources/Runtime/RuntimeRegex.swift:419` の NOTE コメントどおり、`kk_regex_create_with_option` / `kk_regex_create_with_options` が「effective pattern + try compile + fallback + box」ロジックをインライン重複している。コメント案の `createRegexBox(pattern:isLiteral:options:)` 共通ヘルパーへ抽出する

### Runtime コルーチン（コード内 CORO TODO の細分化）
- [ ] DEBT-CORO-002: `Sources/Runtime/RuntimeTypes.swift:490,708` — `RuntimeSequenceCoroutine` / `RuntimeMapCoroutine` の producer/consumer セマフォ ping-pong が GCD スレッド 2 本をイテレーション中ずっとブロック（コード内 TODO(CORO-004)）。yield() を suspend ポイントとしてモデル化する移行をこの 2 型から着手する
- [ ] DEBT-CORO-003: `Sources/Runtime/RuntimeCoroutineContext.swift:691` — `withContext` が continuation 移行途中でセマフォ fallback のまま。continuation ベースへ完了させる

### Sema 近似実装・既知クラッシュ
- [ ] DEBT-SEMA-001: `Sources/CompilerCore/Sema/TypeCheck/Helpers+TypeArgsAndMemberLookup.swift:113-135` の型エイリアス use-site variance 検証が no-op（計算結果を `_ = (declaredVariance, argVariance)` で破棄、`declaredVariance` は三項演算子の両分岐とも `.invariant`）。宣言側 variance を参照した実検証を実装するか、no-op で正しい仕様根拠をコメントへ明記する
- [ ] DEBT-SEMA-002: `Sources/CompilerCore/Sema/DataFlow/OpenFinalOverride.swift:809` 付近のジェネリック戻り値の共変 override チェックが「For now, implement basic checks」の保守的近似。完全な型引数置換ベースへ拡張する。先に現状すり抜ける不正 override ケースを golden 化してから着手する
- [ ] DEBT-SEMA-003: `Sources/CompilerCore/Sema/DataFlow/OpenFinalOverride.swift:959` 付近のモジュール境界の可視性検証（internal override 等）が保守的近似のまま。モジュール FQN 比較ベースの検証を実装する
- [ ] DEBT-SEMA-004: `Sources/CompilerCore/Sema/DataFlow/BodyAnalysis.swift:693` の `typeArgInnerType(.star)` が `fatalError("typeArgInnerType called on .star")` — star projection `<*>` を含む入力でコンパイラ自体がクラッシュしうる。診断付きの安全な経路へ変更し、`<*>` を含む回帰テストを追加する

### KIR / Lowering
- [ ] DEBT-KIR-001: `Sources/CompilerCore/KIR/CallLowerer+SafeMemberCalls.swift:1085-1094` で vtable dispatch が無効化され常に static dispatch へフォールバックしている（「TODO: Re-enable once kk_alloc-based object allocation is in place」）。ブロッカーとされた `kk_alloc` は `Sources/Runtime/RuntimeGC.swift:151` に実装済みのため、前提充足を監査して再有効化を検討する。再有効化時は `VirtualDispatchTests` へ該当経路のケースを追加する
- [ ] DEBT-KIR-003: `Sources/CompilerCore/Lowering/ABILoweringPass+NonThrowingCallees.swift` の手書き約 1,300 行 Set リテラルを `RuntimeABISpec` 由来の導出へ置換する。`RuntimeABIFunctionSpec` に throwing 属性が無いため throwing 情報が二重管理になっている — spec へ `isThrowing` フィールドを追加し、既存手書きリストとの全件突き合わせ検証を経て自動導出へ移行する（RF-LOWER-005 の具体化、RF-KIR-005 / RF-RT-005 とも整合）

### 命名規約違反の解消（恒久ファイルのみ・削除予定コードは対象外）
> CLAUDE.md「分割ファイルは責務ベースで命名」違反。リネームのみで挙動変更なし。
- [ ] DEBT-NAME-001: `+SharedAPI.swift` 4 ファイル（`CallLowerer` / `ControlFlowLowerer` / `LambdaLowerer` / `ObjectLiteralLowerer`、Sources/CompilerCore/KIR/）を機能ベース名（例: `+DispatchEntryPoints`）へリネームする（4 ファイル一括 1 PR）
- [ ] DEBT-NAME-002: `Sources/CompilerCore/KIR/LambdaLowerer+Helpers.swift`（`syntheticLambdaName` 1 関数のみ）を `+SyntheticNaming.swift` へリネームするか本体へ統合する
- [ ] DEBT-NAME-003: `Sources/CompilerCore/Lowering/CollectionLiteralLoweringPass+CallRewriteHelpers.swift`（138 行、ファクトリ/述語テーブル）を内容を表す名前（例: `+FactoryPredicates`）へリネームする
- [ ] DEBT-NAME-004: `Sources/CompilerCore/Sema/TypeCheck/CallTypeChecker+MemberCallUtilities.swift`（194 行、variance 許容チェック等）を内容を表す名前へリネームする

### RuntimeABISpec 本体の分割完遂
> 既に 33 ファイルへ +分割済みだが、本体 `RuntimeABISpec.swift`（3,629 行）に 19 個の `static let *Functions` が残存する。
- [ ] DEBT-ABI-001: `operatorFunctions`（約 508 行）を `RuntimeABISpec+Operator.swift` へ移動する
- [ ] DEBT-ABI-002: `bitwiseFunctions`（約 322 行）を `RuntimeABISpec+Bitwise.swift` へ移動する
- [ ] DEBT-ABI-003: `exceptionFunctions`（約 329 行）を `RuntimeABISpec+Exception.swift` へ移動する
- [ ] DEBT-ABI-004: `delegateFunctions`（約 259 行）/ `boxingFunctions`（約 117 行）ほか残存 static let を + ファイルへ移動し、本体を spec コア型定義 + 集約プロパティのみへ縮小する

### CI / Scripts
- [ ] DEBT-CI-001: `LSPServerTests` が Package.swift にターゲット定義されているのに `.github/workflows/ci.yml` の full-swift-tests マトリクスへ含まれておらず CI 未実行。マトリクスへ追加する
- [ ] DEBT-CI-002: `jscpd-check` / `smoke-tests` ジョブに `timeout-minutes` が未設定（npm install のネットワーク障害等でハングしうる。full-swift-tests は 45 分、diff-regression-shards は 60 分設定済み）。それぞれ適切な値を設定する
- [ ] DEBT-SCRIPT-001: `detect_workers()` が `Scripts/swift_test.sh:9` と `Scripts/diff_kotlinc.sh:344` に同一実装でコピーされている。`Scripts/lib/common.sh` へ抽出し両者から source で共有する

### テスト衛生
- [ ] DEBT-TEST-002: `Tests/CompilerCoreTests/Lowering/LoweringPassRegressionTests.swift:548` と `LoweringABIAndPropertyRegressionTests.swift:6` に同一実装の `private func makeContext(...)` がコピー存在する。`Integration/TestSupport/Pipeline.swift` の `makeCompilationContext()` へ統一する
- [ ] DEBT-TEST-003: `Tests/CompilerCoreTests/Sema/SemaCacheContextTests.swift:8` の `makeContextFromSourceWithCache()` を、`Pipeline.swift` の `makeContextFromSource()` へ `frontendFlags` 引数を追加して統合する
- [ ] DEBT-TEST-004: KIR / Lowering テスト群に散在する `SemaModule(...)` 直接構築（計 90 箇所超: `BuildKIRRegressionTests+ExpressionAndAdvancedScenarios` / `VirtualDispatchTests+InliningCoroutineAndDispatchResolution` / `RuntimeTypeCheckTokenTests` 等）を `makeSemaModule()` ヘルパー利用へ移行する（ファイル単位で分割実施可）
- [ ] DEBT-TEST-005: `Scripts/diff_cases` の `// SKIP-DIFF` / `// KSWIFTK_DIFF_IGNORE` 65 ケースを棚卸しし、各ケースへ対応タスク ID（SPEC-* / PARITY-* / DEBT-*）をコメント付与する。対応タスクが無い skip は新規起票する（skip 放置の防止。SPEC 方法論「修正後にマーカーを外せば回帰テストになる」の運用徹底）

### ドキュメント乖離
- [ ] DEBT-DOC-001: `CLAUDE.md` コーディング規約の「Swift 5.9, macOS 12+」が実態（`Package.swift` は `swift-tools-version: 6.2` / `swiftLanguageModes: [.v6]`）と乖離している。修正する
- [ ] DEBT-DOC-002: `docs/ARCHITECTURE.md` §4 の KIR テーブルへ未記載の実在ファイルを追記する（`CallSupportLowerer` / `ObjectLiteralLowerer` / `KIRLoweringContext` / `ConstantCollector` / `LateinitReadWrapping` / `KClassAnnotationRegistrationLowering` / `MutableCaptureCellHelpers` / `RuntimeTypeCheckToken` 等。RF-HYG-005 はモジュール構成・CI 表のみでファイルテーブルは未カバー）
- [ ] DEBT-DOC-003: `docs/ARCHITECTURE.md` §10 の Lowering パス実行順序へ未記載の実在パスを実行順付きで追記する（`EnumEntriesLoweringPass` / `EnumNameAccessLoweringPass` / `FlowLoweringPass` / `IntegerNarrowingPass` / `JvmOverloadsLoweringPass` / `JvmStaticLoweringPass` / `TailrecLoweringPass` / `ValueClassUnboxingPass`）
- [ ] DEBT-DOC-004: `docs/ARCHITECTURE.md` の「CoroutineLoweringPass (+分割3ファイル)」を実態（`+Analysis` / `+CallRewriting` / `+Flow` / `+FlowInstructionRewrite` / `+LauncherSupport` / `+StateMachine` / `+Synthesis` の 7 分割・計 8 ファイル）へ修正する
## Dead Code 削除タスク（DEADCODE: 2026-06-12 監査）

> 監査方法: (1) 識別子の「宣言数 = 全出現数」（参照ゼロ）による Swift シンボル抽出、(2) Runtime の全 `@_cdecl` 2,839 件について CompilerCore の文字列リテラル / 補間・連結による動的生成（`"\(prefix)_suffix"` 型を含む）/ `StdlibSurfaceSpec` テーブル経由、の全 emit 経路を検証。RF-GOV-004 の dead-code audit 第 1 回に相当。
> 注意: `RuntimeABISpec`(+ABIParity) への登録は ABI 宣言・C ヘッダ生成・リンク検証のみで emit 経路ではない。各削除タスクでは spec/parity 宣言と ABI テストの該当エントリも併せて削除する。
> 検証で ALIVE と確定し**削除禁止**のもの: `kk_atomic_*` 全 32 件（`HeaderHelpers+SyntheticAtomicStubs.swift` の接尾辞補間で emit）、`kk_match_result_destructured_component1..9` / `kk_base64_*`（補間 emit）、`kk_long_range_forEach` / `kk_long_range_map`（`MemberRuntimeDispatch` 経由）、`kk_bits_to_*` / `kk_*_to_bits` / `kk_*_trampoline` / `kk_future_complete` / `kk_flow_stopped` / `kk_with_context_full` / `kk_is_cancellation_exception` / `kk_kclass_register_metadata_v2` / `kk_context_get_dispatcher`（Runtime 内部呼び出し）。`kk_pin_object` / `kk_pinned_get` / `kk_unpin_object` は STDLIB-CINTEROP-FN-009/042 が配線予定のため対象外。
> 完了ゲートは RF-GUARD-005 と同じ（全テスト + golden + `diff_kotlinc.sh` green）。

### Runtime: ファイル丸ごと削除可能（emit 経路なし・テスト参照なし）
- [x] DEADCODE-002: `RuntimeFlowErrorHandling.swift` を削除する（`kk_flow_catch` / `on_completion` / `on_error_resume` / `on_error_return` / `retry` / `retry_when` の 6/6 件が未到達。kotlinx.coroutines 風 Flow エラー演算子はターゲット外）

### Runtime: 未到達 `@_cdecl` エクスポート（関数単位）
- [x] DEADCODE-003: Flow/Channel 系 12 件を削除する — `kk_callback_flow_await_close` / `kk_callback_flow_create`、`kk_channel_flow_create` / `kk_channel_flow_send` / `kk_channel_flow_try_send`、`kk_channel_pipeline_drain`、`kk_channel_send_suspending`、`kk_broadcast_channel_close` / `create` / `send` / `subscribe` / `unsubscribe`（主に `RuntimeCoroutineChannel.swift` / `RuntimeCoroutineFlow.swift`）
- [x] DEADCODE-005: `__string_*` ブリッジ 12 件を削除する — `__string_removePrefix` / `removeRange` / `removeRange_range` / `removeSuffix` / `removeSurrounding` / `removeSurrounding_pair` / `replace` / `replaceFirst` / `replaceRange` / `replace_char` / `replace_char_ignoreCase` / `replace_ignoreCase`（`RuntimeStringStdlib.swift`。同機能は `kk_string_*` 側が配線済みで `__` 版は .kt からも参照ゼロ。RF-RT-003 の「`__` ブリッジ降格」方針との整合を確認の上で削除）

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
