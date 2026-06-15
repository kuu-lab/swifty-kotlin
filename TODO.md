# Kotlin Compiler Remaining Tasks

最終更新: 2026-06-13

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

### スコープパッケージ
- `kotlin`
- `kotlin.annotation`
- `kotlin.collections` / `kotlin.sequences`
- `kotlin.comparisons`
- `kotlin.ranges`
- `kotlin.text`（+ `Char`）
- `kotlin.io`（common のみ）
- `kotlin.io.encoding`（Base64 / HexFormat）
- `kotlin.math` / `kotlin.random`
- `kotlin.concurrent` / `kotlin.concurrent.atomics`
- `kotlin.reflect`
- `kotlin.time`
- `kotlin.properties`
- `kotlin.coroutines` / `kotlin.coroutines.cancellation` / `kotlin.coroutines.intrinsics`
- `kotlin.enums`
- `kotlin.system`
- `kotlin.uuid`
- `kotlin.native` / `kotlin.native.concurrent` / `kotlin.native.ref` / `kotlin.native.runtime`
- `kotlin.contracts`
- `kotlin.experimental`

### Phase 1: プリミティブ・演算子・配列・String コア

### Phase 2: コレクション・Sequence・Range
- [~] STDLIB-022: range / progression / unsigned range の網羅性を上げる（LongRange `firstOrNull` / `lastOrNull` runtime 済み）

#### kotlin.collections 関数の実装（D-Z）

### Phase 3: I/O・パス・時間・並行（common）
- [~] STDLIB-GAP-PH3: `kotlin.io`（common） / `kotlin.time` / `kotlin.concurrent` / `kotlin.concurrent.atomics` の未対応を潰す

#### kotlin.concurrent 型の実装

#### kotlin.concurrent 関数の実装

#### kotlin.concurrent.atomics 型の実装

#### kotlin.contracts 型の実装

#### kotlin.coroutines.cancellation 関数の実装

#### kotlin.io 型の実装

#### kotlin.io プロパティの実装

#### kotlin.io 関数の実装

#### kotlin.io.encoding 型の実装

#### kotlin.io.path プロパティの実装

#### kotlin.io.path 関数の実装
- [x] STDLIB-IO-PATH-FN-011: `createSymbolicLinkPointingTo` 関数の実装
- [ ] STDLIB-IO-PATH-FN-018: `fileVisitor` 関数の実装
- [ ] STDLIB-IO-PATH-FN-019: `forEachDirectoryEntry` 関数の実装
- [x] STDLIB-IO-PATH-FN-030: `readAttributes` 関数の実装
- [x] STDLIB-IO-PATH-FN-028: `outputStream` 関数の実装
- [x] STDLIB-IO-PATH-FN-032: `setAttribute` 関数の実装
- [x] STDLIB-IO-PATH-FN-037: `useDirectoryEntries` 関数の実装
- [ ] STDLIB-IO-PATH-FN-039: `walk` 関数の実装
- [x] STDLIB-IO-PATH-FN-038: `useLines` 関数の実装

#### kotlin.reflect 型の実装

#### kotlin.reflect プロパティの実装

#### kotlin.reflect 関数の実装

#### kotlin.sequences 型の実装

#### kotlin.sequences 関数の実装

#### kotlin.system 関数の実装
- [ ] STDLIB-SYSTEM-FN-004: `getTimeNanos` 関数の実装
- [ ] STDLIB-SYSTEM-FN-003: `getTimeMillis` 関数の実装
- [ ] STDLIB-SYSTEM-FN-007: `measureTimeMillis` 関数の実装
- [ ] STDLIB-SYSTEM-FN-006: `measureTimeMicros` 関数の実装

#### kotlin.text 型の実装

#### kotlin.text プロパティの実装

#### kotlin.text 関数の実装
- [ ] STDLIB-TEXT-FN-003: `append` 関数の実装
- [ ] STDLIB-TEXT-FN-004: `appendLine` 関数の実装
- [ ] STDLIB-TEXT-FN-005: `appendRange` 関数の実装
- [ ] STDLIB-TEXT-FN-006: `buildString` 関数の実装
- [ ] STDLIB-TEXT-FN-007: `buildStringAppend` 関数の実装
- [ ] STDLIB-TEXT-FN-008: `buildStringBuilder` 関数の実装
- [ ] STDLIB-TEXT-FN-010: `codePointCount` 関数の実装
- [ ] STDLIB-TEXT-FN-013: `decodeToString` 関数の実装
- [ ] STDLIB-TEXT-FN-016: `equals` 関数の実装
- [ ] STDLIB-TEXT-FN-019: `indent` 関数の実装
- [ ] STDLIB-TEXT-FN-021: `indexOfAny` 関数の実装
- [ ] STDLIB-TEXT-FN-022: `indexOfFirst` 関数の実装
- [ ] STDLIB-TEXT-FN-023: `indexOfLast` 関数の実装
- [ ] STDLIB-TEXT-FN-024: `insert` 関数の実装
- [ ] STDLIB-TEXT-FN-025: `insertRange` 関数の実装
- [ ] STDLIB-TEXT-FN-026: `intern` 関数の実装
- [ ] STDLIB-TEXT-FN-027: `isBlank` 関数の実装
- [ ] STDLIB-TEXT-FN-031: `isNullOrEmpty` 関数の実装
- [ ] STDLIB-TEXT-FN-033: `iterator` 関数の実装
- [ ] STDLIB-TEXT-FN-034: `lastIndexOf` 関数の実装
- [ ] STDLIB-TEXT-FN-035: `lastIndexOfAny` 関数の実装
- [ ] STDLIB-TEXT-FN-038: `minus` 関数の実装
- [ ] STDLIB-TEXT-FN-039: `onEach` 関数の実装
- [ ] STDLIB-TEXT-FN-040: `onEachIndexed` 関数の実装
- [ ] STDLIB-TEXT-FN-042: `padStart` 関数の実装
- [ ] STDLIB-TEXT-FN-043: `plus` 関数の実装
- [ ] STDLIB-TEXT-FN-044: `random` 関数の実装
- [ ] STDLIB-TEXT-FN-046: `reduce` 関数の実装
- [ ] STDLIB-TEXT-FN-048: `reduceIndexedOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-049: `reduceOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-051: `removeRange` 関数の実装
- [ ] STDLIB-TEXT-FN-053: `removeSurrounding` 関数の実装
- [ ] STDLIB-TEXT-FN-056: `replaceAfter` 関数の実装
- [ ] STDLIB-TEXT-FN-058: `replaceBefore` 関数の実装
- [ ] STDLIB-TEXT-FN-060: `replaceFirst` 関数の実装
- [ ] STDLIB-TEXT-FN-062: `replaceRange` 関数の実装
- [ ] STDLIB-TEXT-FN-065: `setRange` 関数の実装
- [ ] STDLIB-TEXT-FN-067: `singleOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-068: `slice` 関数の実装
- [ ] STDLIB-TEXT-FN-070: `splitToSequence` 関数の実装
- [ ] STDLIB-TEXT-FN-072: `subSequence` 関数の実装
- [ ] STDLIB-TEXT-FN-079: `takeIf` 関数の実装
- [ ] STDLIB-TEXT-FN-081: `takeLastWhile` 関数の実装
- [ ] STDLIB-TEXT-FN-083: `toBigDecimal` 関数の実装
- [ ] STDLIB-TEXT-FN-084: `toBigDecimalOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-085: `toBigInteger` 関数の実装
- [ ] STDLIB-TEXT-FN-086: `toBigIntegerOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-091: `toByteOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-094: `toCollection` 関数の実装
- [ ] STDLIB-TEXT-FN-095: `toDouble` 関数の実装
- [ ] STDLIB-TEXT-FN-107: `toShortOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-115: `withIndex` 関数の実装

#### kotlin.time 型の実装

#### kotlin.time プロパティの実装

#### kotlin.time 関数の実装

#### kotlin.uuid 型の実装

#### kotlin.uuid 関数の実装

### Phase 4: リフレクション・数値・テキスト・その他 stdlib

#### kotlin.comparisons 関数の実装
- [ ] STDLIB-COMP-FN-015: `maxOf` 関数の実装（Float版、3引数）
- [ ] STDLIB-COMP-FN-014: `maxOf` 関数の実装（Float版、2引数）
- [ ] STDLIB-COMP-FN-017: `maxOf` 関数の実装（Int版、2引数）
- [ ] STDLIB-COMP-FN-020: `maxOf` 関数の実装（Long版、2引数）
- [ ] STDLIB-COMP-FN-029: `minOf` 関数の実装（Comparable版、2引数）
- [ ] STDLIB-COMP-FN-030: `minOf` 関数の実装（Comparable版、3引数）
- [ ] STDLIB-COMP-FN-032: `minOf` 関数の実装（Byte版、2引数）
- [ ] STDLIB-COMP-FN-034: `minOf` 関数の実装（Byte版、vararg）
- [ ] STDLIB-COMP-FN-032: `minOf` 関数の実装（Byte版、2引数）
- [ ] STDLIB-COMP-FN-039: `minOf` 関数の実装（Float版、3引数）
- [ ] STDLIB-COMP-FN-035: `minOf` 関数の実装（Double版、2引数）
- [ ] STDLIB-COMP-FN-036: `minOf` 関数の実装（Double版、3引数）
- [ ] STDLIB-COMP-FN-038: `minOf` 関数の実装（Float版、2引数）
- [ ] STDLIB-COMP-FN-039: `minOf` 関数の実装（Float版、3引数）
- [ ] STDLIB-COMP-FN-040: `minOf` 関数の実装（Float版、vararg）
- [ ] STDLIB-COMP-FN-044: `minOf` 関数の実装（Long版、2引数）
- [ ] STDLIB-COMP-FN-046: `minOf` 関数の実装（Long版、vararg）
- [ ] STDLIB-COMP-FN-050: `minOf` 関数の実装（UByte版）
- [ ] STDLIB-COMP-FN-051: `minOf` 関数の実装（UInt版）
- [ ] STDLIB-COMP-FN-052: `minOf` 関数の実装（ULong版）
- [ ] STDLIB-COMP-FN-053: `minOf` 関数の実装（UShort版）
- [ ] STDLIB-COMP-FN-055: `minWith` 関数の実装
- [ ] STDLIB-COMP-FN-059: `nullsFirst` 関数の実装（Comparable版）
- [ ] STDLIB-COMP-FN-061: `nullsLast` 関数の実装（Comparable版）
- [ ] STDLIB-COMP-FN-062: `nullsLast` 関数の実装（Comparator版）

#### kotlin.random 型の実装

#### kotlin.random 関数の実装

- [ ] STDLIB-ANNO-002: annotation sema / diagnostics を整える
- [~] STDLIB-CORO-001: `kotlin.coroutines.intrinsics` / cancellation — 主要部分実装済み（`suspendCoroutineUninterceptedOrReturn`, `intercepted`, `CancellationException`）。残課題は別チケットへ分割。

### Phase 5: 非スコープ/高度領域
- [ ] STDLIB-JS-COLLECTIONS-FN-006: `JsReadonlySet<E>.toSet()` を追加する
- [ ] STDLIB-JS-COLLECTIONS-FN-005: `JsReadonlySet<E>.toMutableSet()` を追加する
- [ ] STDLIB-CINTEROP-TYPE-020: `kotlinx.cinterop.CPointerVarOf<T>` class surface を追加する
- [ ] STDLIB-CINTEROP-FN-010: `place(value)` を追加する
- [ ] STDLIB-CINTEROP-FN-009: `pin()` を追加する
- [ ] STDLIB-CINTEROP-FN-011: `CPointer<T>.plus(index)` を追加する
- [ ] STDLIB-CINTEROP-FN-016: `CPointer<T>.set(index, value)` を追加する
- [ ] STDLIB-CINTEROP-FN-026: `ULongArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-029: `ByteArray.toKString()` を追加する
- [ ] STDLIB-CINTEROP-FN-035: `CPointer<UShortVar>.toKStringFromUtf16()` を追加する
- [ ] STDLIB-CINTEROP-FN-034: `CPointer<ShortVar>.toKStringFromUtf16()` を追加する
- [ ] STDLIB-CINTEROP-FN-018: `ByteArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-024: `UByteArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-025: `UIntArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-028: `List<CPointer<T>?>.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-025: `UIntArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-032: `CPointer<UShortVar>.toKString()` を追加する
- [ ] STDLIB-CINTEROP-FN-041: `CValue<T>.useContents(block)` を追加する
- [ ] STDLIB-CINTEROP-FN-042: `T.usePinned(block)` を追加する
- [ ] STDLIB-CINTEROP-FN-045: `CValue<T>.write(location)` を追加する
- [ ] STDLIB-CINTEROP-FN-044: `vectorOf(Int, Int, Int, Int)` の公式 annotation/signature を既存 stub と整合させる
- [ ] STDLIB-CINTEROP-FN-046: `writeBits(ptr, offset, size, value)` を追加する
- [ ] STDLIB-CINTEROP-FN-047: `zeroValue<T>()` を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-001: `kotlinx.cinterop.internal.CCall` annotation を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-002: `kotlinx.cinterop.internal.CEnumEntryAlias` annotation を追加する
- [ ] STDLIB-CINTEROP-INTERNAL-TYPE-004: `kotlinx.cinterop.internal.CGlobalAccess` annotation を追加する
- [ ] STDLIB-DOM-TYPE-001: `org.w3c.dom.ItemArrayLike<T>` external interface を追加する
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

- [x] MIGRATION-TEXT-001: String 変換・切り出し関数を Kotlin source に移行する（`trim`, `trimStart`, `trimEnd`, `substring`, `subSequence`, `take`, `takeLast`, `drop`, `dropLast`）
- [x] MIGRATION-TEXT-002: String 検索・置換関数を Kotlin source に移行する（`replace`, `replaceFirst`, `replaceRange`, `removeRange`, `removeSuffix`, `removePrefix`, `removeSurrounding`）
- [x] MIGRATION-TEXT-003: String パディング・繰り返し関数を Kotlin source に移行する（`padStart`, `padEnd`, `repeat`, `reversed`）
- [x] MIGRATION-TEXT-004: String 分割・結合関数を Kotlin source に移行する（`split`, `splitToSequence`, `joinToString`, `chunked`, `windowed`, `zipWithNext`, `zip`）
- [x] MIGRATION-TEXT-005: String 大文字小文字・ロケール関数を Kotlin source に移行する（`lowercase`, `uppercase`, `capitalize`, `replaceFirstChar`, locale 版）
- [ ] MIGRATION-TEXT-006: String インデント・フォーマット関数を Kotlin source に移行する（`trimIndent`, `trimMargin`, `prependIndent`, `replaceIndent`, `format`）
- [ ] MIGRATION-TEXT-007: String encode/decode 関数を Kotlin source に移行する（`encodeToByteArray`, `decodeToString`, charset 版含む）
- [ ] MIGRATION-TEXT-008: String HOF 関数を Kotlin source に移行する（`filter`, `filterNot`, `filterIndexed`, `map`, `mapIndexed`, `mapNotNull`, `flatMap`, `fold`, `reduce`, `scan` 等）

### Phase M2: kotlin.text StringBuilder
> 移行元: `Sources/Runtime/RuntimeStringBuilder.swift` (29 @_cdecl)
> 移行先: `Stdlib/kotlin/text/StringBuilder.kt`


### Phase M3: kotlin.collections ファクトリ・HOF
> 移行元: `Sources/Runtime/RuntimeCollectionHOF.swift` (166), `RuntimeCollectionHOFArray.swift` (27), `RuntimeCollectionHOFGrouping.swift` (11), `RuntimeCollectionHOFMaxMin.swift` (26), `RuntimeCollections.swift` (85)
> 移行先: `Stdlib/kotlin/collections/`

- [ ] MIGRATION-COL-002: List 変換 HOF を Kotlin source に移行する（`map`, `mapIndexed`, `mapNotNull`, `flatMap`, `flatten`）
- [ ] MIGRATION-COL-003: List フィルタ HOF を Kotlin source に移行する（`filter`, `filterNot`, `filterNotNull`, `filterIndexed`, `filterIsInstance`）
- [ ] MIGRATION-COL-004: List 集約 HOF を Kotlin source に移行する（`fold`, `foldRight`, `reduce`, `reduceOrNull`, `scan`, `runningFold`）
- [ ] MIGRATION-COL-005: List 検索 HOF を Kotlin source に移行する（`first`, `firstOrNull`, `last`, `lastOrNull`, `single`, `singleOrNull`, `find`, `findLast`, `indexOf`, `indexOfFirst`, `indexOfLast`）
- [ ] MIGRATION-COL-006: List ソート・比較 HOF を Kotlin source に移行する（`sorted`, `sortedBy`, `sortedByDescending`, `sortedWith`, `reversed`, `shuffled`）
- [x] MIGRATION-COL-007: List グルーピング・関連付け HOF を Kotlin source に移行する（`groupBy`, `groupByTo`, `associate`, `associateBy`, `associateWith`, `partition`）
- [x] MIGRATION-COL-008: List 集計 HOF を Kotlin source に移行する（`count`, `any`, `all`, `none`, `maxByOrNull`, `minByOrNull`, `maxWith`, `minWith`, `sumOf`）
- [x] MIGRATION-COL-009: List ウィンドウ・チャンク HOF を Kotlin source に移行する（`chunked`, `windowed`, `zipWithNext`, `zip`, `withIndex`）
- [x] MIGRATION-COL-010: List 部分取得 HOF を Kotlin source に移行する（`take`, `takeLast`, `takeWhile`, `takeLastWhile`, `drop`, `dropLast`, `dropWhile`, `dropLastWhile`, `distinct`, `distinctBy`）
- [x] MIGRATION-COL-011: List ビルダー関数を Kotlin source に移行する（`buildList`, `buildSet`, `buildMap`）
- [x] MIGRATION-COL-012: Map HOF を Kotlin source に移行する（`map.filter`, `filterKeys`, `filterValues`, `mapKeys`, `mapValues`, `mapNotNull`, `flatMap`, `forEach`, `getOrElse`, `getOrDefault`）
- [x] MIGRATION-COL-013: Set HOF を Kotlin source に移行する（`set.filter`, `map`, `flatMap`, `forEach`, `sorted`, `first`, `last`, `count`, `any`, `all`, `none`）

### Phase M4: kotlin.sequences
> 移行元: `Sources/Runtime/RuntimeSequence.swift` (105), `RuntimeSequenceBuilders.swift` (20), `RuntimeSequenceAssociation.swift` (25), `RuntimeSequenceFoldScan.swift` (9)
> 移行先: `Stdlib/kotlin/sequences/`

- [ ] MIGRATION-SEQ-001: Sequence ファクトリを Kotlin source に移行する（`sequenceOf`, `emptySequence`, `generateSequence`, `sequence { }` builder）
- [ ] MIGRATION-SEQ-002: Sequence 変換 HOF を Kotlin source に移行する（`map`, `mapIndexed`, `mapNotNull`, `flatMap`, `flatten`, `filter`, `filterNot`, `filterNotNull`）
- [ ] MIGRATION-SEQ-003: Sequence 端末 HOF を Kotlin source に移行する（`toList`, `toSet`, `toMutableList`, `first`, `firstOrNull`, `last`, `lastOrNull`, `single`, `count`, `any`, `all`, `none`）
- [ ] MIGRATION-SEQ-004: Sequence 集約 HOF を Kotlin source に移行する（`fold`, `reduce`, `scan`, `associate`, `associateBy`, `groupBy`, `sumOf`, `maxByOrNull`, `minByOrNull`）
- [ ] MIGRATION-SEQ-005: Sequence ウィンドウ・制限 HOF を Kotlin source に移行する（`take`, `takeWhile`, `drop`, `dropWhile`, `chunked`, `windowed`, `zip`, `zipWithNext`, `distinct`, `distinctBy`）

### Phase M5: kotlin.comparisons
> 移行元: `Sources/Runtime/RuntimeComparator.swift` (47 @_cdecl)
> 移行先: `Stdlib/kotlin/comparisons/Comparisons.kt`

- [ ] MIGRATION-COMP-001: Comparator ファクトリ・合成を Kotlin source に移行する（`compareBy`, `compareByDescending`, `naturalOrder`, `reverseOrder`, `reversed`, `thenBy`, `thenByDescending`, `thenComparing`）
- [ ] MIGRATION-COMP-002: maxOf/minOf 全オーバーロードを Kotlin source に移行する（Comparable版, プリミティブ版, vararg版）

### Phase M6: kotlin.ranges
> 移行元: `Sources/Runtime/RuntimeRangeAndDispatch.swift` (46), `RuntimeRangeIntRangeHOF.swift` (30), `RuntimeRangeLongRange.swift`, `RuntimeRangeUIntULongRange.swift`
> 移行先: `Stdlib/kotlin/ranges/`

- [ ] MIGRATION-RANGE-001: Range/Progression クラス API を Kotlin source に移行する（`IntRange`, `LongRange`, `CharRange`, `IntProgression`, `LongProgression`, `CharProgression` の iterator/contains/isEmpty）
- [ ] MIGRATION-RANGE-002: Range HOF を Kotlin source に移行する（`forEach`, `map`, `filter`, `toList`, `count`, `first`, `last`, `reversed`, `step`）
- [ ] MIGRATION-RANGE-003: Range ユーティリティを Kotlin source に移行する（`coerceIn`, `coerceAtLeast`, `coerceAtMost`, `until`, `downTo`）

### Phase M7: kotlin.random
> 移行元: `Sources/Runtime/RuntimeRandom.swift` (38 @_cdecl)
> 移行先: `Stdlib/kotlin/random/Random.kt`

- [ ] MIGRATION-RANDOM-001: `Random` クラス API を Kotlin source に移行する（`nextInt`, `nextLong`, `nextDouble`, `nextFloat`, `nextBoolean`, `nextBytes` — PRNG ステート管理はブリッジに委譲）

### Phase M8: kotlin.time / Duration
> 移行元: `Sources/Runtime/RuntimeDuration.swift` (61 @_cdecl)
> 移行先: `Stdlib/kotlin/time/Duration.kt`

- [ ] MIGRATION-TIME-001: `Duration` 算術・変換を Kotlin source に移行する（`plus`, `minus`, `times`, `div`, `unaryMinus`, `absoluteValue`, `isPositive`, `isNegative`, `isInfinite`）
- [ ] MIGRATION-TIME-002: `Duration` コンポーネント・文字列変換を Kotlin source に移行する（`toComponents`, `toString`, `toIsoString`, `inWholeMilliseconds`, `inWholeMicroseconds` 等）
- [ ] MIGRATION-TIME-003: `Duration` ファクトリ拡張を Kotlin source に移行する（`Int.seconds`, `Long.milliseconds`, `Double.minutes` 等の拡張プロパティ）

### Phase M9: kotlin.io File I/O
> 移行元: `Sources/Runtime/RuntimeFileIO.swift` (144 @_cdecl)
> 移行先: `Stdlib/kotlin/io/`

- [ ] MIGRATION-IO-001: File 読み書き関数を Kotlin source に移行する（`readText`, `writeText`, `readBytes`, `writeBytes`, `appendText`, `appendBytes`）
- [ ] MIGRATION-IO-002: File ストリーム・バッファ関数を Kotlin source に移行する（`bufferedReader`, `bufferedWriter`, `inputStream`, `outputStream`, `reader`, `writer`）
- [ ] MIGRATION-IO-003: File 走査・操作関数を Kotlin source に移行する（`walk`, `walkTopDown`, `walkBottomUp`, `copyTo`, `copyRecursively`, `deleteRecursively`, `forEachLine`, `useLines`）

### Phase M10: kotlin.io.encoding
> 移行元: `Sources/Runtime/RuntimeBase64.swift` (26), `RuntimeHexFormat.swift` (18)
> 移行先: `Stdlib/kotlin/io/encoding/`

- [ ] MIGRATION-ENC-001: Base64 encode/decode を Kotlin source に移行する（`Base64.encode`, `Base64.decode`, `Base64.UrlSafe`, `Base64.Mime`）
- [ ] MIGRATION-ENC-002: HexFormat を Kotlin source に移行する（`HexFormat`, `toHexString`, `hexToByteArray`）

### Phase M11: kotlin.text Regex
> 移行元: `Sources/Runtime/RuntimeRegex.swift` (44 @_cdecl)
> 移行先: `Stdlib/kotlin/text/Regex.kt`

- [ ] MIGRATION-REGEX-001: `Regex` クラス API を Kotlin source に移行する（`find`, `findAll`, `matchEntire`, `matches`, `containsMatchIn`, `replace`, `replaceFirst`, `split`）

### Phase M12: kotlin.uuid
> 移行元: `Sources/Runtime/RuntimeUuid.swift` (24 @_cdecl)
> 移行先: `Stdlib/kotlin/uuid/Uuid.kt`

- [ ] MIGRATION-UUID-001: `Uuid` クラス API を Kotlin source に移行する（`Uuid.random`, `Uuid.parse`, `toString`, `toLongs`, `toByteArray`）

### Phase M13: kotlin (Result)
> 移行元: `Sources/Runtime/RuntimeResult.swift` (16 @_cdecl)
> 移行先: `Stdlib/kotlin/Result.kt`

- [ ] MIGRATION-RESULT-001: `Result` クラスと `runCatching` を Kotlin source に移行する（`isSuccess`, `isFailure`, `getOrNull`, `getOrDefault`, `getOrElse`, `getOrThrow`, `map`, `fold`, `onSuccess`, `onFailure`）

### Phase M14: kotlin.properties
> 移行元: `Sources/Runtime/RuntimeDelegates.swift` (41 @_cdecl)
> 移行先: `Stdlib/kotlin/properties/`

- [ ] MIGRATION-PROP-001: Delegate プロパティを Kotlin source に移行する（`Delegates.observable`, `Delegates.vetoable`, `Delegates.notNull`）
- [ ] MIGRATION-PROP-002: `lazy` 関数を Kotlin source に移行する（`lazy {}`, `LazyThreadSafetyMode` 各モード）

### Phase M15: kotlin.reflect
> 移行元: `Sources/Runtime/RuntimeReflection.swift` (55 @_cdecl)
> 移行先: `Stdlib/kotlin/reflect/`

- [ ] MIGRATION-REFLECT-001: `KClass` 基本 API を Kotlin source に移行する（`simpleName`, `qualifiedName`, `isInstance`, `isAbstract`, `isSealed`, `isFinal`）
- [ ] MIGRATION-REFLECT-002: `KClass` メンバ introspection を Kotlin source に移行する（`members`, `constructors`, `nestedClasses`, `supertypes`）

### Phase M16: kotlin.concurrent.atomics
> 移行元: `Sources/Runtime/RuntimeAtomic.swift` (97 @_cdecl)
> 移行先: `Stdlib/kotlin/concurrent/atomics/`

- [ ] MIGRATION-ATOMIC-001: `AtomicInt` / `AtomicLong` / `AtomicRef` の API を Kotlin source に移行する（`get`, `set`, `getAndSet`, `compareAndSet`, `incrementAndGet`, `decrementAndGet`, `addAndGet` — CAS 操作はブリッジに委譲）

### Phase M17: kotlin.collections Set/Map 基本操作
> 移行元: `Sources/Runtime/RuntimeSetAndMap.swift` (53 @_cdecl)
> 移行先: `Stdlib/kotlin/collections/`

- [ ] MIGRATION-SETMAP-001: Set/Map ファクトリ・基本操作を Kotlin source に移行する（`contains`, `containsKey`, `containsValue`, `get`, `getOrDefault`, `keys`, `values`, `entries`, `size`, `isEmpty`）

## ターゲット外バックログ（本体非追跡）
### JS/Wasm/JVM固有のstub削除（Nativeターゲット専用コンパイラのため不要）
#### JS Array関連stub
- [ ] CLEANUP-STUB-004: `kk_js_array_create` stub削除
- [ ] CLEANUP-STUB-003: `kk_js_array_set` stub削除
- [x] CLEANUP-STUB-004: `kk_js_array_create` stub削除
- [ ] CLEANUP-STUB-005: `kk_js_array_toList` stub削除
- [ ] CLEANUP-STUB-006: `kk_js_array_toMutableList` stub削除
#### JS Map関連stub
- [ ] CLEANUP-STUB-007: `kk_js_map_toMap` stub削除
#### JS Set関連stub
- [ ] CLEANUP-STUB-010: `kk_js_set_toMutableSet` stub削除
#### JS型変換関連stub
- [ ] CLEANUP-STUB-012: `kk_js_number_toDouble` stub削除
- [x] CLEANUP-STUB-013: `kk_js_number_toInt` stub削除
- [ ] CLEANUP-STUB-014: `kk_js_boolean_toBoolean` stub削除
- [ ] CLEANUP-STUB-015: `kk_js_reference_get` stub削除
#### Wasm Export stub
#### Wasm Import stub
#### Wasm Unsafe Annotation stub
#### Wasm Unsafe Memory Allocator stub
#### Wasm Unsafe Pointer stub
- [ ] CLEANUP-STUB-020: Wasm Unsafe Pointer stub削除（`HeaderHelpers+SyntheticWasmUnsafePointerStubs.swift`）
#### Wasm Unsafe Scoped Allocator stub
- [ ] CLEANUP-STUB-021: Wasm Unsafe Scoped Allocator stub削除（`HeaderHelpers+SyntheticWasmUnsafeScopedAllocatorStubs.swift`）
#### JVM Time相互運用stub
- [ ] CLEANUP-STUB-022: `kk_java_instant_to_kotlin_instant` stub削除（`HeaderHelpers+SyntheticPlatformTimeConversionStubs.swift`, `RuntimeTime.swift`実装も削除）
- [ ] CLEANUP-STUB-023: `kk_java_duration_to_kotlin_duration` stub削除（`HeaderHelpers+SyntheticPlatformTimeConversionStubs.swift`, `RuntimeTime.swift`実装も削除）
#### JVM Atomic相互運用stub
- [ ] CLEANUP-STUB-024: `kk_java_atomic_int_asKotlinAtomic` stub削除（`HeaderHelpers+SyntheticAtomicStubs.swift`, `RuntimeAtomic.swift`実装も削除）
- [ ] CLEANUP-STUB-025: `kk_java_atomic_long_asKotlinAtomic` stub削除（`HeaderHelpers+SyntheticAtomicStubs.swift`, `RuntimeAtomic.swift`実装も削除）
- [ ] CLEANUP-STUB-026: `kk_java_atomic_bool_asKotlinAtomic` stub削除（`HeaderHelpers+SyntheticAtomicStubs.swift`, `RuntimeAtomic.swift`実装も削除）
- [ ] CLEANUP-STUB-028: `kk_java_atomic_int_array_asKotlinAtomicArray` stub削除（`HeaderHelpers+SyntheticAtomicStubs.swift`, `RuntimeAtomic.swift`実装も削除）
- [ ] CLEANUP-STUB-030: `kk_java_atomic_ref_array_asKotlinAtomicArray` stub削除（`HeaderHelpers+SyntheticAtomicStubs.swift`, `RuntimeAtomic.swift`実装も削除）
#### JVM Random相互運用stub
- [ ] CLEANUP-STUB-031: `kk_java_random_new` stub削除（`HeaderHelpers+SyntheticRandomStubs.swift`, `RuntimeRandom.swift`実装も削除）
- [ ] CLEANUP-STUB-032: `kk_java_random_new_seed` stub削除（`HeaderHelpers+SyntheticRandomStubs.swift`, `RuntimeRandom.swift`実装も削除）
#### JS/Wasm/JVM stub登録呼び出し削除
- [ ] CLEANUP-STUB-033: `HeaderHelpers+SyntheticPhase_PlatformAndJS.swift`の全呼び出し削除
- [x] CLEANUP-STUB-034: `HeaderHelpers+SyntheticPhase_ExtendedStdlib.swift`のJS/Wasm/JVM関連呼び出し削除
#### その他JS固有stub（ファイル単位）
- [ ] CLEANUP-STUB-035: JS Console stub削除（`HeaderHelpers+SyntheticJsConsoleStubs.swift`）
- [ ] CLEANUP-STUB-036: JS Eval stub削除（`HeaderHelpers+SyntheticJsEvalStubs.swift`）
- [ ] CLEANUP-STUB-037: JS Json stub削除（`HeaderHelpers+SyntheticJsJsonStubs.swift`）
- [ ] CLEANUP-STUB-038: JS TypeOf stub削除（`HeaderHelpers+SyntheticJsTypeOfStubs.swift`）
- [ ] CLEANUP-STUB-039: JS ParseInt stub削除（`HeaderHelpers+SyntheticJsParseIntStubs.swift`）
- [ ] CLEANUP-STUB-040: JS ParseIntRadix stub削除（`HeaderHelpers+SyntheticJsParseIntRadixStubs.swift`）
- [ ] CLEANUP-STUB-041: JS ParseFloat stub削除（`HeaderHelpers+SyntheticJsParseFloatStubs.swift`）
- [ ] CLEANUP-STUB-042: JS Function stub削除（`HeaderHelpers+SyntheticJsFunctionStubs.swift`）
- [ ] CLEANUP-STUB-043: JS Class stub削除（`HeaderHelpers+SyntheticJsClassStubs.swift`）
- [x] CLEANUP-STUB-044: JS Module stub削除（`HeaderHelpers+SyntheticJsModuleStubs.swift`）
- [x] CLEANUP-STUB-045: JS Name stub削除（`HeaderHelpers+SyntheticJsNameStubs.swift`）
- [x] CLEANUP-STUB-046: JS NonModule stub削除（`HeaderHelpers+SyntheticJsNonModuleStubs.swift`）
- [ ] CLEANUP-STUB-047: JS Date stub削除（`HeaderHelpers+SyntheticJsDateStubs.swift`）
- [ ] CLEANUP-STUB-048: JS Exception stub削除（`HeaderHelpers+SyntheticJsExceptionStubs.swift`）
- [ ] CLEANUP-STUB-049: JS Promise stub削除（`HeaderHelpers+SyntheticJsPromiseStubs.swift`）
- [ ] CLEANUP-STUB-050: JS RegExpMatch stub削除（`HeaderHelpers+SyntheticJsRegExpMatchStubs.swift`）
- [ ] CLEANUP-STUB-051: JS Static stub削除（`HeaderHelpers+SyntheticJsStaticStubs.swift`）
- [ ] CLEANUP-STUB-052: JS ExternalArgument stub削除（`HeaderHelpers+SyntheticJsExternalArgumentStubs.swift`）
- [ ] CLEANUP-STUB-053: JS ExternalInheritorsOnly stub削除（`HeaderHelpers+SyntheticJsExternalInheritorsOnlyStubs.swift`）
- [ ] CLEANUP-STUB-054: JS DefinedExternally stub削除（`HeaderHelpers+SyntheticJsDefinedExternallyStubs.swift`）
- [ ] CLEANUP-STUB-055: JS String stub削除（`HeaderHelpers+SyntheticJsStringStubs.swift`）
- [ ] CLEANUP-STUB-056: JS StringInterop stub削除（`HeaderHelpers+SyntheticJsStringInteropStubs.swift`）
- [x] CLEANUP-STUB-057: JS Qualifier stub削除（`HeaderHelpers+SyntheticJsQualifierStubs.swift`）
- [x] CLEANUP-STUB-047: JS Date stub削除（`HeaderHelpers+SyntheticJsDateStubs.swift`）
- [x] CLEANUP-STUB-048: JS Exception stub削除（`HeaderHelpers+SyntheticJsExceptionStubs.swift`）
- [x] CLEANUP-STUB-049: JS Promise stub削除（`HeaderHelpers+SyntheticJsPromiseStubs.swift`）
- [x] CLEANUP-STUB-050: JS RegExpMatch stub削除（`HeaderHelpers+SyntheticJsRegExpMatchStubs.swift`）
- [x] CLEANUP-STUB-051: JS Static stub削除（`HeaderHelpers+SyntheticJsStaticStubs.swift`）
- [x] CLEANUP-STUB-052: JS ExternalArgument stub削除（`HeaderHelpers+SyntheticJsExternalArgumentStubs.swift`）
- [x] CLEANUP-STUB-053: JS ExternalInheritorsOnly stub削除（`HeaderHelpers+SyntheticJsExternalInheritorsOnlyStubs.swift`）
- [x] CLEANUP-STUB-054: JS DefinedExternally stub削除（`HeaderHelpers+SyntheticJsDefinedExternallyStubs.swift`）
- [x] CLEANUP-STUB-055: JS String stub削除（`HeaderHelpers+SyntheticJsStringStubs.swift`）
- [x] CLEANUP-STUB-056: JS StringInterop stub削除（`HeaderHelpers+SyntheticJsStringInteropStubs.swift`）
- [ ] CLEANUP-STUB-057: JS Qualifier stub削除（`HeaderHelpers+SyntheticJsQualifierStubs.swift`）
- [ ] CLEANUP-STUB-058: JS BigIntInterop stub削除（`HeaderHelpers+SyntheticJsBigIntInteropStubs.swift`）
- [x] CLEANUP-STUB-059: JS NumberInterop stub削除（`HeaderHelpers+SyntheticJsNumberInteropStubs.swift`）
- [ ] CLEANUP-STUB-060: JS ReferenceInterop stub削除（`HeaderHelpers+SyntheticJsReferenceInteropStubs.swift`）
- [ ] CLEANUP-STUB-063: JS PrimitiveWrappers stub削除（`HeaderHelpers+SyntheticJsPrimitiveWrappers.swift`）
- [ ] CLEANUP-STUB-064: JS CollectionsArray stub削除（`HeaderHelpers+SyntheticJsCollectionsArrayStubs.swift`）
- [ ] CLEANUP-STUB-065: JS CollectionsMap stub削除（`HeaderHelpers+SyntheticJsCollectionsMapStubs.swift`）
- [ ] CLEANUP-STUB-066: JS CollectionsSet stub削除（`HeaderHelpers+SyntheticJsCollectionsSetStubs.swift`）
- [ ] CLEANUP-STUB-067: JS CollectionsReadonlyArray stub削除（`HeaderHelpers+SyntheticJsCollectionsReadonlyArrayStubs.swift`）
- [ ] CLEANUP-STUB-066: JS CollectionsSet stub削除（`HeaderHelpers+SyntheticJsCollectionsSetStubs.swift`）
- [ ] CLEANUP-STUB-068: JS CollectionsReadonlySet stub削除（`HeaderHelpers+SyntheticJsCollectionsReadonlySetStubs.swift`）
- [ ] CLEANUP-STUB-069: JS CollectionsReadonlyMap stub削除（`HeaderHelpers+SyntheticJsCollectionsReadonlyMapToMapStubs.swift`）
- [ ] CLEANUP-STUB-072: JS Fun stub削除（`HeaderHelpers+SyntheticJsFunStubs.swift`）
- [ ] CLEANUP-STUB-071: JS Any stub削除（`HeaderHelpers+SyntheticJsAnyStubs.swift`）
- [ ] CLEANUP-STUB-073: JS Export stub削除（`HeaderHelpers+SyntheticJsExportStubs.swift`）
- [ ] CLEANUP-STUB-074: JS FileName stub削除（`HeaderHelpers+SyntheticJsFileNameStubs.swift`）
- [ ] CLEANUP-STUB-074: JS FileName stub削除（`HeaderHelpers+SyntheticJsFileNameStubs.swift`）
- [ ] CLEANUP-STUB-075: JS BigIntToLong stub削除（`HeaderHelpers+SyntheticJsBigIntToLongStubs.swift`）
- [ ] CLEANUP-STUB-076: JS BigInt stub削除（`HeaderHelpers+SyntheticJsBigIntStubs.swift`）
- [ ] CLEANUP-STUB-077: JS Boolean stub削除（`HeaderHelpers+SyntheticJsBooleanStubs.swift`）
- [ ] CLEANUP-STUB-079: JS Reference stub削除（`HeaderHelpers+SyntheticJsReferenceStubs.swift`）
- [ ] CLEANUP-STUB-078: JS Number stub削除（`HeaderHelpers+SyntheticJsNumberStubs.swift`）
- [ ] CLEANUP-STUB-080: JS RegExp stub削除（`HeaderHelpers+SyntheticJsRegExpStubs.swift`）
- [ ] CLEANUP-STUB-081: JS Stubs（メイン）削除（`HeaderHelpers+SyntheticJsStubs.swift`）
- [ ] CLEANUP-STUB-082: JVM AnnotationProperty stub削除（`HeaderHelpers+SyntheticJvmAnnotationPropertyStubs.swift`）
- [ ] CLEANUP-STUB-084: JVM Metaprog stub削除（`HeaderHelpers+SyntheticMetaprogStubs.swift`）
- [ ] CLEANUP-STUB-083: JVM Reflect stub削除（`HeaderHelpers+SyntheticJvmReflectStubs.swift`）
- [x] CLEANUP-STUB-084: JVM Metaprog stub削除（`HeaderHelpers+SyntheticMetaprogStubs.swift`）
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
- [ ] TEST-SEQ-009: `kotlin.sequences` の `findLast` / `partition` に Runtime テストを追加する。`kk_sequence_findLast` / `kk_sequence_partition` は専用ランタイム実装があるのに `Tests/RuntimeTests/RuntimeSequenceTests*.swift` での参照が 0 件。カバー対象: 空シーケンス・単一要素・マッチなし（`findLast` は `null`）・全要素マッチ・`partition` の predicate による 2 分割（`Pair<List, List>`）。`count` は基本ケース（`testCountReturnsElementCount`）のみ存在のため、空シーケンスと `predicate` 版を補完する
- [ ] TEST-CORO-003: 高度な Coroutine 機能テスト（29→40）
- [ ] TEST-CI-007: CI パイプラインの最適化
- [ ] TEST-SEQ-010: `kotlin.sequences` 既存関数のエッジケースを拡充する。`distinctBy`（空・全要素同一キー・キーセレクタ例外伝播）、`filterIsInstance`（空・全一致・全不一致）、`reduceIndexed` / `reduceRightIndexed`（単一要素で accumulator 未呼出）、および中間操作の遅延評価回数の検証（`RuntimeSequenceTests+BuilderAndAdvanced.swift` の `_lazyTestYieldCounter` 機構を活用）
- [ ] TEST-COL-012: `kotlin.collections` の `Set` 高階関数の Runtime/Codegen テストを追加する。`kk_set_filter` / `filterNot` / `map` / `flatMap` / `all` / `any` / `first` / `last` / `lastOrNull` / `maxOrNull` / `minOrNull` / `sorted` / `sortedDescending` / `singleOrNull` / `count{}`（`kk_set_count_predicate`）/ `forEach` は実装の実体が `RuntimeCollectionHOF.swift` にあるが、Runtime テストも Codegen 統合テストも存在しない（Set 専用テストファイルが皆無）。カバー対象: 空 Set・単一要素・全一致/全不一致・要素順序・`first`/`last` の空 Set で例外。`none` と `mapNotNull` は既存カバー済みのため対象外
- [ ] TEST-COL-014: `kotlin.collections` の `List` 受信者版 `reduceIndexedOrNull` / `scanIndexed` の Codegen 統合テストを追加する。Sequence 受信者版はカバー済みだが List 受信者の実行テストが欠落。カバー対象: 空（`reduceIndexedOrNull` は `null`、`scanIndexed` は initial のみ）・単一要素・accumulator に渡る index の検証
- [ ] TEST-RANGE-015: `kotlin.ranges` の IntRange/LongRange 受信者の HOF 実行テストを追加する。`forEach` / `drop` / `take` / `sorted` / `average` / `mapIndexed` / `mapNotNull` / `filterIndexed` / `findLast` / `reduceIndexed` / `first`(predicate版) / `last`(predicate版) は実装ありだが実行レベルのテストが無い（`KotlinCompilationBasicTests` は KIR コンパイルのみで実行せず、`forEach`/`drop`/`take`/`sorted`/`average` は KIR すら未通過）。`RuntimeRangeHOFTests` の直接 `kk_range_*` 呼び出しか Codegen 統合（`.kt` 実行）で。カバー対象: 空 range・単一要素・降順 progression（step 負）・`average` の整数→Double 変換。IntRange の `mapIndexed` は直接ギャップ（UInt/ULong 版は既存）
- [ ] TEST-COMP-011: `kotlin.comparisons` の Comparator 合成を補強する。`naturalOrder` / `reverseOrder` のトランポリンに `runtimeNullSentinelInt` を渡したときの挙動、`compareBy` で全キー等値のとき `0` を返すこと、参照型オブジェクトの厳密な安定ソート（同値要素の原順序保持をインデックスベースで検証）。既存 `RuntimeComparatorTests.swift` は充実しているため上記の隙間に限定する
- [ ] TEST-COL-013: `kotlin.collections` の `Map` 高階関数 `getOrDefault` / `flatMap` / `mapNotNull` / `maxByOrNull` / `minByOrNull` の Codegen 統合テストを追加する（`RuntimeSetAndMap.swift` 等に実装ありだが実行テストなし）。カバー対象: 空 Map・キー不在時の `getOrDefault` デフォルト返却・全エントリ変換・`maxByOrNull`/`minByOrNull` の空 Map で `null`
- [ ] TEST-MATH-022: `kotlin.math` の `pow` IEEE 特殊ケースの実行テストを追加する。`pow(負, 非整数)`=NaN / `pow(0.0, 負)`=+Inf / `pow(-0.0, 負の奇数整数)`=-Inf / `pow(-1.0, ±Inf)`=1.0 / `pow(+Inf, 負)`=+0.0 が未テスト（`RuntimeMathEdgeCaseTests` は `Inf^-1`/`NaN^0`/`1^NaN` のみで負底・分数指数の特殊表が欠落）。Double/Float/Int 各 overload（`kk_math_pow`/`pow_float`/`pow_int`/`pow_float_int`）でカバー
- [ ] TEST-MATH-023: `kotlin.math` の 2引数 `log(x, base)` と `log2`/`log10` のドメイン端の実行テストを追加する。`log(x, base)` の `base≤0`/`base==1`→NaN、`x<0`→NaN、`x=0`→-Inf、`x`/`base` が `+Inf` の組合せ。`log2`/`log10` の `0`→-Inf・`負`→NaN・`+Inf`→+Inf（既存は `1→0` と NaN のみ）
- [ ] TEST-MATH-024: `kotlin.math` の符号付きゼロ・負無限大の対称性ギャップを埋める。`floor(-0.0)`/`truncate(±0.0)` の符号保持、`cbrt(-0.0)=-0.0`/`cbrt(-Inf)=-Inf`、`sinh(-Inf)=-Inf`/`cosh(-Inf)=+Inf`/`tanh(-Inf)=-1.0`、`atanh(-1.0)=-Inf`、`tan(Inf)=NaN`、`atan2` の IEEE 特殊ケース表（`atan2(±0,±0)`/`atan2(±y,±Inf)`/`atan2(±Inf, finite)`/`atan2(NaN,*)`）、`nextUp(-Inf)`/`nextDown(+Inf)`、`ulp(Float NaN)`、`sign(Float NaN)`/`sign(+0.0)`。既存は「正側のみテスト・負側未テスト」の偏りがある
- [ ] TEST-MATH-025: `roundToInt`/`roundToLong` の NaN 挙動を Kotlin 仕様と照合・是正する【監査/潜在バグ】。現状 `kk_double_roundToInt`/`kk_double_roundToLong`/`kk_float_*` は NaN で `0` を返し `RuntimeMathTests.swift:93` がそれを是認しているが、Kotlin の `Double.roundToInt()` 仕様は NaN で `IllegalArgumentException` を投げる。`Scripts/diff_kotlinc.sh` で実挙動を確認し、乖離なら runtime を例外送出へ修正（+テスト更新）、意図的逸脱なら理由を明記。±Inf→`Int.MAX/MIN` 飽和は現状維持

## 公式ドキュメント整合性チェック（Kotlin docs parity）

Kotlin 公式 stdlib ドキュメントと実行時挙動を突き合わせて確認した結果を順次記録する。`[x]` は本リポジトリで修正済み、`[ ]` は未対応の残課題。検証は Swift Foundation の `CharacterSet` / `Unicode.Scalar.Properties` の実挙動を実機で確認した上で判断している。

### kotlin.text Char（2026-05-31 検証）
- [ ] DOCPARITY-CHAR-005: `Int.digitToChar()` / `Int.digitToChar(radix)` が言語レベルに未配線。ランタイム `kk_char_digitToChar_radix` は存在するが Sema synthetic stub が無く、Kotlin ソースから `digit.digitToChar(radix)` を呼べない。`Char.digitToInt(radix)` 同様に `Int` 拡張の synthetic stub を `HeaderHelpers+SyntheticCharStubs.swift` 系へ追加する（無 radix 版 `digitToChar()` も含む）。
- [ ] DOCPARITY-CHAR-006: `Char.digitToIntOrNull(radix)` のランタイム/配線が無い（無 radix 版 `kk_char_digitToIntOrNull` のみ）。公式には `fun Char.digitToIntOrNull(radix: Int): Int?` が存在するため、`kk_char_digitToInt_radix` の非例外版を追加し synthetic stub を配線する。
- [ ] DOCPARITY-CHAR-007: `Char.isLetter()` 以外の `CharacterSet` 依存述語（`isDigit` は Nd で一致確認済み・問題なし）について、`isJavaIdentifierStart/Part` 等の未実装述語を含めて公式カテゴリ規則との突き合わせを継続する。

## Kotlin 挙動 parity（kotlinc 2.3.10 比較で発見した差分）

> `Scripts/diff_kotlinc.sh` を実 kotlinc 2.3.10（Swift 6.2 + LLVM 18）で実行して検出。`// KSWIFTK_DIFF_IGNORE` ケースは `--force-run-skipped` で再現可能。

- [ ] PARITY-NUM-001: Int/Long/UInt の 32/64bit オーバーフロー・シフトが未実装（**重大・アーキテクチャ**）。native backend が全整数を i64 で表現し、Int(32bit) の演算結果を切り詰めず、シフト量もマスクしない（Int は `& 31`、Long は `& 63`）。
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
- [ ] SPEC-NUM-0002: 整数のゼロ除算・剰余が catch 可能な `ArithmeticException`（"/ by zero"）を投げず、ハードウェア SIGFPE でプロセスが異常終了する（catch 不能）。codegen で除数のゼロチェックを挿入する必要あり。浮動小数のゼロ除算（Infinity/NaN）は正しい。再現: `Scripts/diff_cases/num_div_by_zero.kt`（SKIP-DIFF）。
- [ ] SPEC-NUM-0003: `Double`/`Float` の関係演算子（`<` `<=` `>` `>=`）が IEEE-754 比較（NaN は常に false）ではなく `Comparable.compareTo`（全順序、NaN 最大）経由になり、`1.0 < Double.NaN`→`true`（正: `false`）等。`compareTo` 束縛を外すと OperatorLoweringPass が被演算子の Double ランクを検出できず（`arena.exprType` が nil）整数比較 `kk_op_lt` に落ち、負の double 比較を壊すため、KIR 型伝播の改善（または専用 IEEE 比較 desugar）とセットで対応が必要。再現: `Scripts/diff_cases/num_nan_comparison.kt`（SKIP-DIFF）。
- [ ] SPEC-NUM-0006: `Double.MIN_VALUE`/`Float.MIN_VALUE` の最短10進表現が `java.lang.*.toString` と異なる（Kotlin: `4.9E-324`/`1.4E-45`、kswiftk: `5.0E-324`/`1.0E-45`）。Swift の最短表現と Java の FloatingDecimal の差。subnormal 端の完全一致は別途。再現: `Scripts/diff_cases/num_float_min_value.kt`（SKIP-DIFF）。
- [ ] SPEC-NUM-0007: 符号なし型のコンパニオン定数 `UInt`/`ULong`/`UByte`/`UShort.MAX_VALUE`/`MIN_VALUE` が未解決（`KSWIFTK-SEMA-0024`）。加えて `UInt.toByte()` や `String.toUByteOrNull()` 等の一部変換/パーサが未配線。再現: `Scripts/diff_cases/num_unsigned_limits.kt`（SKIP-DIFF）。

## 全体リファクタリング計画（RF0–RF8）

> 調査日: 2026-06-10。実測: CompilerCore ~229k 行（うち Sema/DataFlow ~104k、合成スタブ約100ファイル/~9万行）、
> Runtime ~63k 行、Tests ~214k 行、`interner.resolve == "名前"` 特例 104 箇所（TypeCheck）、`"kk_` リテラル 6,738 箇所（CompilerCore）。
> 方針: (1) 削除予定コードは磨かない（リネーム・分割をしない） (2) 各タスクは独立 PR サイズ
> (3) 完了ゲートは既存の `swift_test.sh` / golden / `diff_kotlinc.sh` / jscpd を流用
> (4) M1–M17・CLEANUP-STUB-001〜084 とは重複させず、本計画はその「前提基盤」と「それ以外の負債」を扱う。

### Phase RF0: 計測・ガードレール（他フェーズの前提・即着手可）
- [ ] RF-GUARD-001: LoC メトリクススクリプト `Scripts/loc_report.sh` を追加する（ディレクトリ別行数 / `HeaderHelpers+Synthetic*` 合計行数 / `"kk_` リテラル数 / `interner.resolve == "..."` 数 / Sources 全体 TODO+FIXME 件数 を TSV 出力）。ベースライン値を `docs/refactoring-metrics.md` に記録する（RF-LOWER-001 計測: KIR 2 件・Lowering 2 件・Sources 合計 21 件・Sources+Tests 28 件、2026-06-14 時点）
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
- [x] RF-LOWER-001: KIR + Lowering の TODO/FIXME を triage する（即修正 / タスク化 / 削除の 3 分類。件数を RF-GUARD-001 メトリクスへ組み込み）— 実際は 4 件（KIR 2・Lowering 2、推定 620 は大幅過大）。DEBT-KIR-001・RF-LOWER-002・RF-LOWER-003 にすべて追跡済み。タグなし TODO 2 件に (RF-LOWER-003) を付与
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
- [ ] DEBT-RT-002: `Sources/Runtime/RuntimeStringStdlib.swift:3369` 付近の `trimMargin` が marginPrefix 空白時に `fatalError("IllegalArgumentException: ...")` する。catch 可能な例外送出へ置換する
- [ ] DEBT-RT-003: `Sources/Runtime/RuntimeRegex.swift` の正規表現フォールバック失敗時 `fatalError` 4 箇所（238 / 439 / 471 / 755 付近）を整理する。pattern はユーザー入力直通。静的フォールバック `(?!)` が失敗し得ないことの検証コメント化、または例外送出化
- [ ] DEBT-RT-004: Runtime の非構造化 `fatalError`（構造化パニック `runtimePanicDiagnosticCode` / `KSwiftK panic [診断コード]` を経由しない約 25 箇所）を棚卸しし、診断コード付き構造化パニックへ寄せる
- [x] DEBT-RT-005: `Sources/Runtime/RuntimeNumericCompat.swift:1690` 付近の `kk_char_get` が index != 0 で replacement char（U+FFFD）を返す暫定実装（「For now」コメントあり)を kotlinc 実挙動と突き合わせ、乖離していれば修正する（diff ケース追加）
- [ ] DEBT-RT-006: `Sources/Runtime/RuntimeRegex.swift:419` の NOTE コメントどおり、`kk_regex_create_with_option` / `kk_regex_create_with_options` が「effective pattern + try compile + fallback + box」ロジックをインライン重複している。コメント案の `createRegexBox(pattern:isLiteral:options:)` 共通ヘルパーへ抽出する

### Runtime コルーチン（コード内 CORO TODO の細分化）
- [x] DEBT-CORO-001: `Sources/Runtime/RuntimeCoroutineChannel.swift:20` — closed sentinel が `Int.min` の in-band 設計のため `Long.MIN_VALUE` を Channel 送信できない（コード内 TODO(CORO-001)）。`kk_coroutine_check_cancellation` と同じ status+value のポインタ渡し（out-of-band）へ移行する
- [ ] DEBT-CORO-002: `Sources/Runtime/RuntimeTypes.swift:490,708` — `RuntimeSequenceCoroutine` / `RuntimeMapCoroutine` の producer/consumer セマフォ ping-pong が GCD スレッド 2 本をイテレーション中ずっとブロック（コード内 TODO(CORO-004)）。yield() を suspend ポイントとしてモデル化する移行をこの 2 型から着手する
- [ ] DEBT-CORO-003: `Sources/Runtime/RuntimeCoroutineContext.swift:691` — `withContext` が continuation 移行途中でセマフォ fallback のまま。continuation ベースへ完了させる
- [x] DEBT-CORO-004: `Sources/Runtime/RuntimeCoroutine.swift:617` — `awaitResult()` のセマフォブロッキングを suspend ポイント化する（ファイル冒頭 105-135 行の移行計画の残件）

### Sema 近似実装・既知クラッシュ
- [ ] DEBT-SEMA-001: `Sources/CompilerCore/Sema/TypeCheck/Helpers+TypeArgsAndMemberLookup.swift:113-135` の型エイリアス use-site variance 検証が no-op（計算結果を `_ = (declaredVariance, argVariance)` で破棄、`declaredVariance` は三項演算子の両分岐とも `.invariant`）。宣言側 variance を参照した実検証を実装するか、no-op で正しい仕様根拠をコメントへ明記する
- [ ] DEBT-SEMA-002: `Sources/CompilerCore/Sema/DataFlow/OpenFinalOverride.swift:809` 付近のジェネリック戻り値の共変 override チェックが「For now, implement basic checks」の保守的近似。完全な型引数置換ベースへ拡張する。先に現状すり抜ける不正 override ケースを golden 化してから着手する
- [ ] DEBT-SEMA-003: `Sources/CompilerCore/Sema/DataFlow/OpenFinalOverride.swift:959` 付近のモジュール境界の可視性検証（internal override 等）が保守的近似のまま。モジュール FQN 比較ベースの検証を実装する
- [ ] DEBT-SEMA-004: `Sources/CompilerCore/Sema/DataFlow/BodyAnalysis.swift:693` の `typeArgInnerType(.star)` が `fatalError("typeArgInnerType called on .star")` — star projection `<*>` を含む入力でコンパイラ自体がクラッシュしうる。診断付きの安全な経路へ変更し、`<*>` を含む回帰テストを追加する
- [x] DEBT-SEMA-005: 型エイリアス（`ArrayList` 等）をタイプ位置（変数宣言・引数型）で使う golden テストを追加する（`HeaderHelpers+SyntheticComparableAndCollectionStubs.swift:426` の既知 TODO）

### KIR / Lowering
- [ ] DEBT-KIR-001: `Sources/CompilerCore/KIR/CallLowerer+SafeMemberCalls.swift:1085-1094` で vtable dispatch が無効化され常に static dispatch へフォールバックしている（「TODO: Re-enable once kk_alloc-based object allocation is in place」）。ブロッカーとされた `kk_alloc` は `Sources/Runtime/RuntimeGC.swift:151` に実装済みのため、前提充足を監査して再有効化を検討する。再有効化時は `VirtualDispatchTests` へ該当経路のケースを追加する
- [ ] DEBT-KIR-002: `Sources/CompilerCore/KIR/CallLowerer+LegacySafeMemberCalls.swift`（325 行、compatibility entry point コメントあり）と `CallLowerer+SafeMemberCalls.swift` の二重管理を統合し、Legacy 側を削除する（RF-KIR-001〜003 は `+LegacyMemberLikeCalls` のみ対象で本ファイルは未カバー）
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
- [x] DEBT-SCRIPT-002: `Scripts/baselines/` を削除（`bench_compile.sh` / `save_baseline.sh` は 2026-03 意図削除済みで README のみ孤立。計測は `-Xfrontend time-phases` + `PhaseTimer` / `FrontendParallelBenchmarkTests` で継続）
- [ ] DEBT-SCRIPT-003: `Scripts/test_templates/`（diff / lexer / parser / sema の 4 サブディレクトリ）がスクリプト・CI・ソースのどこからも参照されていない。用途を調査し、README へ用途を明記するか削除する

### テスト衛生
- [x] DEBT-TEST-001: 冒頭で無条件 `XCTSkip` する「未実装」プレースホルダーテストの skip 理由の鮮度を監査する。例: `CodegenBackendIntegrationTests+PropertyDelegateEdgeCases.swift:7` は「Property delegates ... are not yet implemented」とするが `HeaderHelpers+SyntheticPropertyDelegateStubs.swift`（2,741 行）等の実装が既に存在し stale の疑い。実装済みなら skip を解除し、未実装なら対応タスク ID を skip メッセージへ付記する（対象: PropertyDelegate / MathRuntime / CoroutineCancellation / CoroutineBase / EnumEdgeCoverage / Math / Annotation の各 EdgeCases 冒頭、KotlinTextEdgeCases L83・L1122、CharPredicates L113）
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
- [ ] DEADCODE-001: `RuntimeLogging.swift`（`kk_slf4j_*` 20 件が全て未到達）と `RuntimeLoggingAdvanced.swift`（`kk_adv_logger_*` / `kk_mdc_*` / appender 系 19 件が全て未到達）を削除する。SLF4J/MDC/Appender はターゲット外（「JVM 風ロギングフレームワーク互換」）で Sema 側 stub も存在せず、`Scripts/diff_cases/logging_basic.kt` は SKIP-DIFF のため実行経路なし。`kk_file_appender_new` / `kk_rolling_appender_new` / `kk_structured_appender_new` / `kk_async_appender_wrap_*` と `RuntimeABISpec+ABIParity.swift` の対応宣言（約 39 件）も同時に削除する
- [ ] DEADCODE-002: `RuntimeFlowErrorHandling.swift` を削除する（`kk_flow_catch` / `on_completion` / `on_error_resume` / `on_error_return` / `retry` / `retry_when` の 6/6 件が未到達。kotlinx.coroutines 風 Flow エラー演算子はターゲット外）

### Runtime: 未到達 `@_cdecl` エクスポート（関数単位）
- [ ] DEADCODE-003: Flow/Channel 系 12 件を削除する — `kk_callback_flow_await_close` / `kk_callback_flow_create`、`kk_channel_flow_create` / `kk_channel_flow_send` / `kk_channel_flow_try_send`、`kk_channel_pipeline_drain`、`kk_channel_send_suspending`、`kk_broadcast_channel_close` / `create` / `send` / `subscribe` / `unsubscribe`（主に `RuntimeCoroutineChannel.swift` / `RuntimeCoroutineFlow.swift`）
- [ ] DEADCODE-004: リフレクション系 32 件を削除する — `kk_kconstructor_*` 全 12 件、`kk_kclass_get_field_count` / `get_instance_size_words` / `get_qualified_name` / `get_simple_name` / `get_superclass_name` / `is_data_class` / `is_sealed_class` / `is_value_class`、`kk_kproperty_get` / `set` / `stub_get_value` / `stub_getter` / `stub_set_getter` / `stub_set_setter` / `stub_set_value` / `stub_setter`、`kk_callable_ref_call_0..3`（主に `RuntimeReflection.swift`（55 件中 22 件）と `RuntimeDelegates.swift`。KClass/KProperty の生きている経路は別名で配線済み）
- [ ] DEADCODE-005: `__string_*` ブリッジ 12 件を削除する — `__string_removePrefix` / `removeRange` / `removeRange_range` / `removeSuffix` / `removeSurrounding` / `removeSurrounding_pair` / `replace` / `replaceFirst` / `replaceRange` / `replace_char` / `replace_char_ignoreCase` / `replace_ignoreCase`（`RuntimeStringStdlib.swift`。同機能は `kk_string_*` 側が配線済みで `__` 版は .kt からも参照ゼロ。RF-RT-003 の「`__` ブリッジ降格」方針との整合を確認の上で削除）
- [ ] DEADCODE-006: java.time / JS Date 相互運用 14 件を削除する — `kk_java_duration_nano` / `of_millis` / `of_seconds` / `seconds` / `to_millis` / `to_string`、`kk_java_instant_epoch_seconds` / `nano_of_second` / `of_epoch_milli` / `of_epoch_second` / `to_epoch_milli` / `to_string`、`kk_js_date_from_epoch_millis` / `to_string`（`RuntimeTime.swift`。CLEANUP-STUB-022/023/047 の Runtime 側補完。JVM/JS 相互運用はターゲット外）
- [ ] DEADCODE-007: HTTP/Network 系 6 件を削除する — `kk_http_client_clearAuthentication` / `get_async` / `post` / `setBasicAuth` / `setDefaultHeader`、`kk_http_response_contentType`（`RuntimeNetwork.swift`。HTTP 面全体がターゲット外だが、他の `kk_http_*` は Sema stub から emit されるため、まず未到達 6 件のみ。残りは DEADCODE-012 の棚卸しで判定）
- [ ] DEADCODE-008: コルーチン系 8 件を削除する — `kk_kxmini_async_await_throwing` / `async_with_dispatcher` / `run_loop`、`kk_coroutine_scope_cancel_propagate` / `scope_get_parent`、`kk_context_get_exception_handler`、`kk_await_all`、`kk_async_task_cancel`
- [ ] DEADCODE-009: Array HOF 8 件を削除する — `kk_array_filterIndexed` / `filterNot` / `filterNotNull` / `first` / `firstOrNull` / `last` / `lastOrNull` / `mapIndexed`（`RuntimeCollectionHOFArray.swift`。Array 受信者のこれらは `StdlibSurfaceSpec.collectionHOF*` テーブルにも載っておらず別経路で lowering される）
- [x] DEADCODE-010: 数値・GC・その他散在 24 件を削除する — `kk_double_coerceAtLeast_range` / `coerceAtMost_range`、`kk_float_coerceAtLeast_range` / `coerceAtMost_range`、`kk_long_coerceAtLeast_range` / `coerceAtMost_range`、`kk_math_e` / `kk_math_pi`、`kk_char_get` / `kk_char_plus`、`kk_clock_gettime_realtime`、`kk_mem_scope_alloc` / `enter` / `exit`、`kk_native_alloc_bytes` / `heap_alloc` / `heap_free`、`kk_panic`、`kk_write_barrier`、`kk_hexformat_prefix` / `suffix`、`kk_timedvalue_toString`、`kk_path_equals`、`kk_sequence_builder_yieldAll_iterator`（`yieldAll` 3 オーバーロードは全て無印 `kk_sequence_builder_yieldAll` に束縛済み）

### CompilerCore / LSPServer / RuntimeABI: 参照ゼロの Swift シンボル
- [ ] DEADCODE-011: 参照ゼロの Swift 宣言 7 件を削除する — `StdlibSurfaceSpec.collectionHOFRuntimeLinkNames(ownerKind:)`（`Sources/RuntimeABI/StdlibSurfaceSpec.swift:127`、単数形 `collectionHOFRuntimeLinkName` のみ使用）、`DocumentStore.allURIs()`（`Sources/LSPServer/DocumentStore.swift:67`）、`PositionResolver.enclosingDecl(at:)`（`Sources/LSPServer/PositionResolver.swift:39`）、`runtimeParallelStreamElements(from:)`（`Sources/Runtime/RuntimeParallel.swift:50`）、ネスト関数 `buildBoolCondition`（`Sources/CompilerCore/Codegen/NativeEmitter+FunctionEmission.swift:331`）、`runtimeRetainObjectHandle` と `typealias ComparatorLambda`（`Sources/Runtime/RuntimeCollectionHelpers.swift:525-528`）

### テストのみ参照（fiction 棚卸し — 配線するか、テストごと削除するか）
- [~] DEADCODE-012: CompilerCore から emit されないがテストが直接呼ぶ `kk_*` 119 件を領域単位で棚卸しする（fiction 解消: Sema/lowering へ配線するか、テストごと削除するかを判定）。内訳: `kk_http_*` 14、`kk_set_*` 6、`kk_parallel_*` 6、`kk_float_*` 6、`kk_double_*` 6、`kk_int_*` 5、`kk_kproperty_stub_*` 4、`kk_flow_*` 4、`kk_coroutine_*` 4 ほか。特に `kk_set_*`（TEST-COL-012）と `kk_range_contains`（TEST-RANGE-015）は既存テストタスクが「実装あり」を前提にしている fiction なので優先的に解消する。意図的なテストシーム（`kk_runtime_force_reset` / `kk_runtime_heap_object_count` / `kk_assertions_*` 等）は維持してよい。リスト再生成は監査方法（冒頭注記）参照。**2026-06-14 棚卸し結果**: (A) kk_set_* 6件 → 全て ALIVE 確認済み（StdlibSurfaceSpec+SetHOF / CallLowerer isSetLikeType / CollectionLiteralLoweringPass の三経路で emit されている。maxOrNull/minOrNull は Sema externalLinkName 汎用パス経由で ALIVE 確認済み（`Set<Int>.maxOrNull()/minOrNull()` のコンパイル＆実行で検証）。(B) kk_range_contains → IntRange.contains() の externalLinkName を kk_op_contains から kk_range_contains に変更して配線完了（本コミット）。overflow 保護付き実装が `x in range` と `range.contains(x)` の両パスで使われるようになった。(C) kk_http_* テスト参照 14件・kk_parallel_* 6件・kk_double_toJsNumber・kk_int_toJsNumber・kk_flow_emit_with_timestamp → テストごと削除（DEADCODE-015 で対処）。(D) kk_kproperty_stub_create_full/is_const/is_lateinit/visibility → DEADCODE-004 で一括削除。(E) 数値定数 kk_double_max_value/min_value/nan/infinity・kk_float_同上・kk_int_max_value/min_value → Kotlin companion object プロパティとして Sema 配線が必要（DEADCODE-016 で対処）。(F) kk_float_to_bits/kk_double_to_bits → `Double.toBits()`/`Float.toBits()` として配線が必要（DEADCODE-016 で対処）。(G) kk_int_coerceAtLeast_range/coerceAtMost_range/coerceIn_range → `coerceIn(range: IntRange)` overload として配線が必要（DEADCODE-016 で対処）。(H) kk_flow_count/fold/reduce → Flow 標準 HOF として配線が必要（DEADCODE-016 で対処）。(I) kk_coroutine_cancel/name_get/scope_is_active/scope_is_cancelled → コルーチン制御 API として配線が必要（DEADCODE-016 で対処）
- [ ] DEADCODE-013: テストのみ参照の Swift シンボル約 20 件を棚卸しする — `PhaseTimer.exportTSV` / `exportJSON`、`KotlinParser.canStartTypeArguments`、`KotlinLanguageVersion` / `CompilerVersion`（`CompilerTypes.swift`、製品コードから未使用）、`BlockScope` / `validateExpectActualLinks` / `setTypeParameterUpperBound` / `hasContractReturnsNotNull`（`SemanticsModels.swift`）、`smartCastTypeForWhenSubjectCase`、DataFlow の `invalidateVariable` / `narrowToNonNull`、`IncrementalCompilationCache.clearCache`、`SemaCacheContext.invalidateScope`、`FileFingerprint.mtimeUnchanged`、`DependencyGraph.clearFile`、`RuntimeMetadataCodec` / `compilerPluginMetadata`（`RuntimeMetadata.swift`）、`RuntimeReflectionMetadataDecoder`、`completeCancellationIfNeeded`（`RuntimeCoroutine.swift:962`）、`runtimeDetectMemoryLeak`、`RuntimeABIExterns.externDecl`。意図的シーム（`Driver.runForTesting` / `RuntimeABISpec.generateCHeader` / `GoldenHarnessAPI.loadCasesOrCrash` / `renderInSubprocess`）は対象外

- [ ] DEADCODE-015: DEADCODE-012 棚卸しで「テストごと削除」と判定した fiction テストを削除する — (1) `Tests/RuntimeTests/RuntimeHTTPClientTests.swift` と `Tests/RuntimeTests/RuntimeNetworkTests.swift` の HTTP 系テストを削除（`kk_http_client_get` / `kk_http_client_new` / `kk_http_client_send` / `kk_http_client_setBearerToken` / `kk_http_client_setConnectTimeoutMillis` / `kk_http_client_setFollowRedirects` / `kk_http_client_setReadTimeoutMillis` / `kk_http_client_post_async` / `kk_http_request_builder_build` / `kk_http_response_errorMessage` / `kk_http_response_header` / `kk_http_response_isSuccessful` / `kk_http_response_timedOut` / `kk_http_response_url` — HTTP はターゲット外、RuntimeABISpec+Parallel.swift の対応エントリも削除）。(2) `Tests/RuntimeTests/RuntimeParallelTests.swift` を削除（`kk_parallel_pool_new` / `kk_parallel_stream_from_collection` / `kk_parallel_stream_to_list` / `kk_parallel_stream_map` / `kk_parallel_stream_forEach` / `kk_parallel_stream_reduce` — java.util.stream は JVM 専用でターゲット外、RuntimeABISpec+Parallel.swift と Sources/Runtime/RuntimeParallel.swift も削除）。(3) `kk_double_toJsNumber` / `kk_int_toJsNumber` / `kk_flow_emit_with_timestamp` を参照するテストケースを削除（JS ターゲット専用 / 非標準 API）。各削除に際して RuntimeABISpec の対応エントリとテスト参照を同時に除去する
- [ ] DEADCODE-016: DEADCODE-012 棚卸しで「配線が必要」と判定した未配線 kk_* を Sema/lowering に接続する — (A) 数値定数（`kk_double_max_value` / `kk_double_min_value` / `kk_double_nan` / `kk_double_positive_infinity` / `kk_double_negative_infinity` / `kk_float_max_value` / `kk_float_min_value` / `kk_float_nan` / `kk_float_positive_infinity` / `kk_float_negative_infinity` / `kk_int_max_value` / `kk_int_min_value`）: Kotlin の `Double.MAX_VALUE` 等 companion object プロパティとして Sema stub を追加し lowering で emit。(B) ビット変換（`kk_float_to_bits` / `kk_double_to_bits`）: `Float.toBits()` / `Double.toBits()` の明示的呼び出しを emit するよう Sema stub を追加。(C) range coerce overload（`kk_int_coerceAtLeast_range` / `kk_int_coerceAtMost_range` / `kk_int_coerceIn_range`）: `Int.coerceIn(range: IntRange)` の range 受け取り overload を配線。(D) Flow HOF（`kk_flow_count` / `kk_flow_fold` / `kk_flow_reduce`）: Flow の終端演算子を Sema stub から lowering 経由で emit。(E) コルーチン制御（`kk_coroutine_cancel` / `kk_coroutine_name_get` / `kk_coroutine_scope_is_active` / `kk_coroutine_scope_is_cancelled`）: CoroutineScope / CoroutineName / Job の API を Sema stub から lowering 経由で emit。各項目で配線完了後に Codegen 統合テストを追加する

### 未監査領域（フォローアップ）
- [ ] DEADCODE-014: 今回未監査の領域を同手法で監査する — Runtime の C コード（GC 等の .c/.h）、診断コード `KSWIFTK-*` の未発行コード、stored property / global 定数、Tests 内ヘルパ、`Scripts/diff_cases` の SKIP-DIFF ケースの実行可否。以降は RF-GOV-004 の四半期運用に乗せる
