# Kotlin Compiler Remaining Tasks

最終更新: 2026-06-10

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
- [x] STDLIB-004: `Array` / primitive array の生成・変換・境界挙動を整理する
- [x] STDLIB-GAP-PH1: ギャップ表の `kotlin` / `kotlin.text` / `Array` 周辺の未対応を潰す

### Phase 2: コレクション・Sequence・Range
- [~] STDLIB-022: range / progression / unsigned range の網羅性を上げる（LongRange `firstOrNull` / `lastOrNull` runtime 済み）

#### kotlin.collections 関数の実装（D-Z）
- [x] STDLIB-COL-FN-073: `firstNotNullOfOrNull` 関数の実装
- [x] STDLIB-COL-FN-074: `firstOrNull` 関数の実装
- [x] STDLIB-COL-FN-075: `flatMap` 関数の実装

### Phase 3: I/O・パス・時間・並行（common）
- [~] STDLIB-GAP-PH3: `kotlin.io`（common） / `kotlin.time` / `kotlin.concurrent` / `kotlin.concurrent.atomics` の未対応を潰す

#### kotlin.concurrent 型の実装
- [x] STDLIB-030: `kotlin.io` common 範囲の file / buffered / `use` を仕様単位で締める

#### kotlin.concurrent 関数の実装

#### kotlin.concurrent.atomics 型の実装

#### kotlin.contracts 型の実装

#### kotlin.coroutines.cancellation 関数の実装

#### kotlin.io 型の実装
- [x] STDLIB-IO-TYPE-004: `FileTreeWalk` クラスの実装
- [x] STDLIB-IO-TYPE-007: `OnErrorAction` enum の実装

#### kotlin.io プロパティの実装
- [x] STDLIB-IO-PROP-003: `invariantSeparatorsPath` 拡張プロパティの実装
- [x] STDLIB-IO-PROP-004: `isRooted` 拡張プロパティの実装

#### kotlin.io 関数の実装
- [x] STDLIB-IO-FN-001: `appendBytes` 関数の実装
- [x] STDLIB-IO-FN-007: `bufferedReader` 関数の実装（InputStream版）
- [x] STDLIB-IO-FN-009: `bufferedWriter` 関数の実装（OutputStream版）
- [x] STDLIB-IO-FN-010: `bufferedWriter` 関数の実装（File版）
- [x] STDLIB-IO-FN-011: `byteInputStream` 関数の実装
- [x] STDLIB-IO-FN-012: `copyRecursively` 関数の実装
- [x] STDLIB-IO-FN-014: `copyTo` 関数の実装（Reader版）
- [x] STDLIB-IO-FN-016: `forEachBlock` 関数の実装
- [x] STDLIB-IO-FN-017: `forEachLine` 関数の実装（Reader版）
- [x] STDLIB-IO-FN-020: `inputStream` 関数の実装（ByteArray版）
- [x] STDLIB-IO-FN-021: `inputStream` 関数の実装（ByteArray範囲版）
- [x] STDLIB-IO-FN-024: `normalize` 関数の実装
- [x] STDLIB-IO-FN-029: `readBytes` 関数の実装（InputStream版）
- [x] STDLIB-IO-FN-030: `readBytes` 関数の実装（URL版）
- [x] STDLIB-IO-FN-033: `readText` 関数の実装（Reader版）
- [x] STDLIB-IO-FN-038: `toRelativeString` 関数の実装
- [x] STDLIB-IO-FN-040: `useLines` 関数の実装（Reader版）

#### kotlin.io.encoding 型の実装

#### kotlin.io.path プロパティの実装

#### kotlin.io.path 関数の実装
- [ ] STDLIB-IO-PATH-FN-011: `createSymbolicLinkPointingTo` 関数の実装
- [ ] STDLIB-IO-PATH-FN-018: `fileVisitor` 関数の実装
- [ ] STDLIB-IO-PATH-FN-019: `forEachDirectoryEntry` 関数の実装
- [ ] STDLIB-IO-PATH-FN-023: `getOwner` 関数の実装
- [ ] STDLIB-IO-PATH-FN-026: `moveTo` 関数の実装
- [ ] STDLIB-IO-PATH-FN-028: `outputStream` 関数の実装
- [ ] STDLIB-IO-PATH-FN-030: `readAttributes` 関数の実装
- [ ] STDLIB-IO-PATH-FN-032: `setAttribute` 関数の実装
- [x] STDLIB-IO-PATH-FN-037: `useDirectoryEntries` 関数の実装
- [ ] STDLIB-IO-PATH-FN-038: `useLines` 関数の実装
- [x] STDLIB-IO-PATH-FN-039: `walk` 関数の実装
- [ ] STDLIB-IO-PATH-FN-040: `writeLines` 関数の実装（Iterable版）
- [x] STDLIB-IO-PATH-FN-042: `writer` 関数の実装

#### kotlin.reflect 型の実装
- [x] STDLIB-REFLECT-TYPE-009: `KMutableProperty` インターフェースの実装
- [x] STDLIB-REFLECT-TYPE-010: `KMutableProperty0` インターフェースの実装
- [x] STDLIB-REFLECT-TYPE-013: `KParameter` インターフェースの実装
- [x] STDLIB-REFLECT-TYPE-015: `KProperty0` インターフェースの実装

#### kotlin.reflect プロパティの実装

#### kotlin.reflect 関数の実装

#### kotlin.sequences 型の実装

#### kotlin.sequences 関数の実装
- [x] STDLIB-SEQ-FN-005: `associate` 関数の実装
- [x] STDLIB-SEQ-FN-009: `associateWith` 関数の実装
- [x] STDLIB-SEQ-FN-044: `forEach` 関数の実装
- [x] STDLIB-SEQ-FN-046: `groupBy` 関数の実装
- [x] STDLIB-SEQ-FN-047: `groupByTo` 関数の実装
- [x] STDLIB-SEQ-FN-087: `plus` 関数の実装

#### kotlin.system 関数の実装
- [x] STDLIB-SYSTEM-FN-001: `exitProcess` 関数の実装
- [ ] STDLIB-SYSTEM-FN-003: `getTimeMillis` 関数の実装
- [ ] STDLIB-SYSTEM-FN-004: `getTimeNanos` 関数の実装
- [x] STDLIB-SYSTEM-FN-005: `measureNanoTime` 関数の実装
- [ ] STDLIB-SYSTEM-FN-006: `measureTimeMicros` 関数の実装
- [ ] STDLIB-SYSTEM-FN-007: `measureTimeMillis` 関数の実装

#### kotlin.text 型の実装
- [x] STDLIB-TEXT-TYPE-008: `MatchGroupCollection` インターフェースの実装
- [x] STDLIB-TEXT-TYPE-010: `MatchResult` インターフェースの実装

#### kotlin.text プロパティの実装
- [x] STDLIB-TEXT-PROP-003: `directionality` 拡張プロパティの実装
- [x] STDLIB-TEXT-PROP-008: `isIdentifierIgnorable` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-009: `isJavaIdentifierPart` 拡張プロパティの実装
- [x] STDLIB-TEXT-PROP-010: `isJavaIdentifierStart` 拡張プロパティの実装
- [x] STDLIB-TEXT-PROP-015: `isSurrogate` 拡張プロパティの実装
- [x] STDLIB-TEXT-PROP-016: `isTitleCase` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-017: `isUnicodeIdentifierPart` 拡張プロパティの実装

#### kotlin.text 関数の実装
- [ ] STDLIB-TEXT-FN-003: `append` 関数の実装
- [ ] STDLIB-TEXT-FN-004: `appendLine` 関数の実装
- [ ] STDLIB-TEXT-FN-005: `appendRange` 関数の実装
- [ ] STDLIB-TEXT-FN-006: `buildString` 関数の実装
- [ ] STDLIB-TEXT-FN-007: `buildStringAppend` 関数の実装
- [ ] STDLIB-TEXT-FN-008: `buildStringBuilder` 関数の実装
- [x] STDLIB-TEXT-FN-009: `capitalize` 関数の実装
- [ ] STDLIB-TEXT-FN-010: `codePointCount` 関数の実装
- [ ] STDLIB-TEXT-FN-013: `decodeToString` 関数の実装
- [x] STDLIB-TEXT-FN-014: `encodeToByteArray` 関数の実装
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
- [x] STDLIB-TEXT-FN-055: `replace` 関数の実装
- [ ] STDLIB-TEXT-FN-056: `replaceAfter` 関数の実装
- [ ] STDLIB-TEXT-FN-058: `replaceBefore` 関数の実装
- [ ] STDLIB-TEXT-FN-060: `replaceFirst` 関数の実装
- [ ] STDLIB-TEXT-FN-062: `replaceRange` 関数の実装
- [ ] STDLIB-TEXT-FN-065: `setRange` 関数の実装
- [ ] STDLIB-TEXT-FN-067: `singleOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-068: `slice` 関数の実装
- [ ] STDLIB-TEXT-FN-070: `splitToSequence` 関数の実装
- [ ] STDLIB-TEXT-FN-072: `subSequence` 関数の実装
- [x] STDLIB-TEXT-FN-074: `substringAfter` 関数の実装
- [x] STDLIB-TEXT-FN-075: `substringAfterLast` 関数の実装
- [x] STDLIB-TEXT-FN-077: `substringBeforeLast` 関数の実装
- [ ] STDLIB-TEXT-FN-079: `takeIf` 関数の実装
- [ ] STDLIB-TEXT-FN-081: `takeLastWhile` 関数の実装
- [x] STDLIB-TEXT-FN-082: `takeWhile` 関数の実装
- [ ] STDLIB-TEXT-FN-083: `toBigDecimal` 関数の実装
- [ ] STDLIB-TEXT-FN-084: `toBigDecimalOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-085: `toBigInteger` 関数の実装
- [ ] STDLIB-TEXT-FN-086: `toBigIntegerOrNull` 関数の実装
- [x] STDLIB-TEXT-FN-088: `toBooleanStrict` 関数の実装
- [x] STDLIB-TEXT-FN-089: `toBooleanStrictOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-091: `toByteOrNull` 関数の実装
- [x] STDLIB-TEXT-FN-092: `toByteArray` 関数の実装
- [ ] STDLIB-TEXT-FN-094: `toCollection` 関数の実装
- [ ] STDLIB-TEXT-FN-095: `toDouble` 関数の実装
- [x] STDLIB-TEXT-FN-096: `toDoubleOrNull` 関数の実装
- [x] STDLIB-TEXT-FN-098: `toFloatOrNull` 関数の実装
- [x] STDLIB-TEXT-FN-101: `toList` 関数の実装
- [x] STDLIB-TEXT-FN-102: `toLong` 関数の実装
- [x] STDLIB-TEXT-FN-104: `toMutableList` 関数の実装
- [x] STDLIB-TEXT-FN-105: `toRegex` 関数の実装
- [x] STDLIB-TEXT-FN-106: `toShort` 関数の実装
- [ ] STDLIB-TEXT-FN-107: `toShortOrNull` 関数の実装
- [x] STDLIB-TEXT-FN-108: `toSortedSet` 関数の実装
- [ ] STDLIB-TEXT-FN-115: `withIndex` 関数の実装
- [x] STDLIB-TEXT-FN-116: `zip` 関数の実装

#### kotlin.time 型の実装
- [x] STDLIB-TIME-TYPE-005: `Duration` クラスの実装
- [x] STDLIB-TIME-TYPE-007: `ExperimentalTime` アノテーションの実装
- [x] STDLIB-TIME-TYPE-009: `TestTimeSource` クラスの実装
- [x] STDLIB-TIME-TYPE-010: `TimedValue` クラスの実装
- [x] STDLIB-TIME-TYPE-012: `TimeSource` インターフェースの実装

#### kotlin.time プロパティの実装
- [x] STDLIB-TIME-PROP-001: `isDistantFuture` 拡張プロパティの実装

#### kotlin.time 関数の実装
- [x] STDLIB-TIME-FN-001: `asClock` 関数の実装
- [x] STDLIB-TIME-FN-002: `measureTime` 関数の実装
- [x] STDLIB-TIME-FN-004: `times` 関数の実装
- [x] STDLIB-TIME-FN-005: `toDuration` 関数の実装
- [x] STDLIB-TIME-FN-006: `toDurationUnit` 関数の実装
- [x] STDLIB-TIME-FN-007: `toJavaDuration` 関数の実装
- [x] STDLIB-TIME-FN-008: `toJavaInstant` 関数の実装
- [x] STDLIB-TIME-FN-009: `toJSDate` 関数の実装
- [x] STDLIB-TIME-FN-010: `toKotlinDuration` 関数の実装
- [x] STDLIB-TIME-FN-012: `toTimeUnit` 関数の実装

#### kotlin.uuid 型の実装

#### kotlin.uuid 関数の実装
- [ ] STDLIB-UUID-FN-002: `putUuid` 関数の実装
#### kotlin.uuid 関数の実装
- [x] STDLIB-UUID-FN-002: `putUuid` 関数の実装
- [x] STDLIB-UUID-FN-004: `toKotlinUuid` 関数の実装

### Phase 4: リフレクション・数値・テキスト・その他 stdlib
- [x] STDLIB-REFLECT-067: `KClass` / metadata / メンバ introspection の残差を詰める
- [x] STDLIB-RANDOM-001: `kotlin.random` の対象 API 一覧を固定
- [x] STDLIB-RANDOM-002: `kotlin.random` の sema / lowering を整える
- [x] STDLIB-COMP-001: `kotlin.comparisons` の対象 API 一覧を固定
- [x] STDLIB-COMP-002: `Comparator` 合成の sema / lowering を整える

#### kotlin.comparisons 関数の実装
- [x] STDLIB-COMP-FN-002: `compareByDescending` 関数の実装（selector版）
- [x] STDLIB-COMP-FN-003: `compareValues` 関数の実装
- [x] STDLIB-COMP-FN-005: `maxOf` 関数の実装（Comparable版、2引数）
- [x] STDLIB-COMP-FN-007: `maxOf` 関数の実装（Comparable版、vararg）
- [x] STDLIB-COMP-FN-009: `maxOf` 関数の実装（Byte版、3引数）
- [x] STDLIB-COMP-FN-010: `maxOf` 関数の実装（Byte版、vararg）
- [ ] STDLIB-COMP-FN-011: `maxOf` 関数の実装（Double版、2引数）
- [x] STDLIB-COMP-FN-012: `maxOf` 関数の実装（Double版、3引数）
- [ ] STDLIB-COMP-FN-014: `maxOf` 関数の実装（Float版、2引数）
- [ ] STDLIB-COMP-FN-015: `maxOf` 関数の実装（Float版、3引数）
- [ ] STDLIB-COMP-FN-017: `maxOf` 関数の実装（Int版、2引数）
- [ ] STDLIB-COMP-FN-020: `maxOf` 関数の実装（Long版、2引数）
- [ ] STDLIB-COMP-FN-022: `maxOf` 関数の実装（Long版、vararg）
- [x] STDLIB-COMP-FN-024: `maxOf` 関数の実装（Short版、3引数）
- [x] STDLIB-COMP-FN-028: `maxWithOrNull` 関数の実装
- [ ] STDLIB-COMP-FN-029: `minOf` 関数の実装（Comparable版、2引数）
- [ ] STDLIB-COMP-FN-030: `minOf` 関数の実装（Comparable版、3引数）
- [x] STDLIB-COMP-FN-032: `minOf` 関数の実装（Byte版、2引数）
- [x] STDLIB-COMP-FN-030: `minOf` 関数の実装（Comparable版、3引数）
- [ ] STDLIB-COMP-FN-032: `minOf` 関数の実装（Byte版、2引数）
- [ ] STDLIB-COMP-FN-034: `minOf` 関数の実装（Byte版、vararg）
- [ ] STDLIB-COMP-FN-032: `minOf` 関数の実装（Byte版、2引数）
- [x] STDLIB-COMP-FN-034: `minOf` 関数の実装（Byte版、vararg）
- [ ] STDLIB-COMP-FN-039: `minOf` 関数の実装（Float版、3引数）
- [ ] STDLIB-COMP-FN-035: `minOf` 関数の実装（Double版、2引数）
- [ ] STDLIB-COMP-FN-036: `minOf` 関数の実装（Double版、3引数）
- [ ] STDLIB-COMP-FN-038: `minOf` 関数の実装（Float版、2引数）
- [ ] STDLIB-COMP-FN-039: `minOf` 関数の実装（Float版、3引数）
- [ ] STDLIB-COMP-FN-040: `minOf` 関数の実装（Float版、vararg）
- [x] STDLIB-COMP-FN-041: `minOf` 関数の実装（Int版、2引数）
- [x] STDLIB-COMP-FN-043: `minOf` 関数の実装（Int版、vararg）
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
- [x] STDLIB-RANDOM-TYPE-001: `Random` abstract class の実装

#### kotlin.random 関数の実装
- [x] STDLIB-RANDOM-FN-001: `Random(seed: Int)` ファクトリ関数の実装
- [x] STDLIB-RANDOM-FN-002: `Random(seed: Long)` ファクトリ関数の実装
- [x] STDLIB-RANDOM-FN-010: `nextBits(bitCount: Int)` 関数の実装
- [x] STDLIB-RANDOM-FN-011: `nextBoolean()` 関数の実装
- [x] STDLIB-RANDOM-FN-012: `nextBytes(array: ByteArray)` 関数の実装
- [x] STDLIB-RANDOM-FN-013: `nextBytes(size: Int)` 関数の実装
- [x] STDLIB-RANDOM-FN-014: `nextBytes(array: ByteArray, fromIndex: Int, toIndex: Int)` 関数の実装
- [x] STDLIB-RANDOM-FN-015: `nextDouble()` 関数の実装
- [x] STDLIB-RANDOM-FN-016: `nextDouble(until: Double)` 関数の実装
- [x] STDLIB-RANDOM-FN-017: `nextDouble(from: Double, until: Double)` 関数の実装
- [x] STDLIB-RANDOM-FN-018: `nextFloat()` 関数の実装
- [x] STDLIB-RANDOM-FN-019: `nextFloat(until: Float)` 関数の実装
- [x] STDLIB-RANDOM-FN-020: `nextFloat(from: Float, until: Float)` 関数の実装
- [x] STDLIB-RANDOM-FN-021: `nextInt()` 関数の実装
- [x] STDLIB-RANDOM-FN-022: `nextInt(until: Int)` 関数の実装
- [x] STDLIB-RANDOM-FN-023: `nextInt(from: Int, until: Int)` 関数の実装
- [x] STDLIB-RANDOM-FN-024: `nextInt(range: IntRange)` 関数の実装
- [x] STDLIB-RANDOM-FN-025: `nextLong()` 関数の実装
- [x] STDLIB-RANDOM-FN-026: `nextLong(until: Long)` 関数の実装
- [x] STDLIB-RANDOM-FN-027: `nextLong(from: Long, until: Long)` 関数の実装
- [x] STDLIB-RANDOM-FN-028: `nextLong(range: LongRange)` 関数の実装
- [x] STDLIB-RANDOM-FN-029: `nextUBytes(size: Int)` 関数の実装
- [x] STDLIB-RANDOM-FN-030: `nextUBytes(array: UByteArray)` 関数の実装
- [x] STDLIB-RANDOM-FN-031: `nextUBytes(array: UByteArray, fromIndex: Int, toIndex: Int)` 関数の実装
- [x] STDLIB-RANDOM-FN-032: `nextUInt()` 関数の実装
- [x] STDLIB-RANDOM-FN-033: `nextUInt(until: UInt)` 関数の実装
- [x] STDLIB-RANDOM-FN-034: `nextUInt(from: UInt, until: UInt)` 関数の実装
- [x] STDLIB-RANDOM-FN-035: `nextUInt(range: UIntRange)` 関数の実装
- [x] STDLIB-RANDOM-FN-036: `nextULong()` 関数の実装
- [x] STDLIB-RANDOM-FN-037: `nextULong(until: ULong)` 関数の実装
- [x] STDLIB-RANDOM-FN-038: `nextULong(from: ULong, until: ULong)` 関数の実装
- [x] STDLIB-RANDOM-FN-039: `nextULong(range: ULongRange)` 関数の実装
- [x] STDLIB-RANDOM-FN-050: `java.util.Random.asKotlinRandom()` 拡張関数の実装
- [x] STDLIB-RANDOM-FN-051: `Random.asJavaRandom()` 拡張関数の実装

- [ ] STDLIB-ANNO-002: annotation sema / diagnostics を整える
- [~] STDLIB-CORO-001: `kotlin.coroutines.intrinsics` / cancellation — 主要部分実装済み（`suspendCoroutineUninterceptedOrReturn`, `intercepted`, `CancellationException`）。残課題は別チケットへ分割。

### Phase 5: 非スコープ/高度領域
- [x] STDLIB-IO-PATH-FN-074: `Path.visitFileTree(maxDepth, followLinks, builderAction)` を追加する
- [x] STDLIB-JS-COLLECTIONS-TYPE-003: `kotlin.js.collections.JsReadonlyArray<E>` external interface を追加する
- [ ] STDLIB-JS-COLLECTIONS-TYPE-004: `kotlin.js.collections.JsReadonlyMap<K, V>` external interface を追加する
- [ ] STDLIB-JS-COLLECTIONS-FN-006: `JsReadonlySet<E>.toSet()` を追加する
- [ ] STDLIB-JS-COLLECTIONS-FN-005: `JsReadonlySet<E>.toMutableSet()` を追加する
- [x] STDLIB-CINTEROP-TYPE-020: `kotlinx.cinterop.CPointerVarOf<T>` class surface を追加する
- [ ] STDLIB-CINTEROP-FN-010: `place(value)` を追加する
- [ ] STDLIB-CINTEROP-FN-009: `pin()` を追加する
- [ ] STDLIB-CINTEROP-FN-011: `CPointer<T>.plus(index)` を追加する
- [ ] STDLIB-CINTEROP-FN-016: `CPointer<T>.set(index, value)` を追加する
- [ ] STDLIB-CINTEROP-FN-026: `ULongArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-029: `ByteArray.toKString()` を追加する
- [ ] STDLIB-CINTEROP-FN-035: `CPointer<UShortVar>.toKStringFromUtf16()` を追加する
- [ ] STDLIB-CINTEROP-FN-034: `CPointer<ShortVar>.toKStringFromUtf16()` を追加する
- [ ] STDLIB-CINTEROP-FN-017: `Array<CPointer<T>?>.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-018: `ByteArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-024: `UByteArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-025: `UIntArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-028: `List<CPointer<T>?>.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-032: `CPointer<UShortVar>.toKString()` を追加する
- [x] STDLIB-CINTEROP-FN-036: `CPointer<IntVar>.toKStringFromUtf32()` を追加する
- [ ] STDLIB-CINTEROP-FN-038: `CPointer<T>?.toLong()` を追加する
- [x] STDLIB-CINTEROP-FN-039: `typeOf<T>()` を追加する
- [ ] STDLIB-CINTEROP-FN-036: `CPointer<IntVar>.toKStringFromUtf32()` を追加する
- [x] STDLIB-CINTEROP-FN-038: `CPointer<T>?.toLong()` を追加する
- [ ] STDLIB-CINTEROP-FN-039: `typeOf<T>()` を追加する
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

- [ ] MIGRATION-TEXT-001: String 変換・切り出し関数を Kotlin source に移行する（`trim`, `trimStart`, `trimEnd`, `substring`, `subSequence`, `take`, `takeLast`, `drop`, `dropLast`）
- [x] MIGRATION-TEXT-002: String 検索・置換関数を Kotlin source に移行する（`replace`, `replaceFirst`, `replaceRange`, `removeRange`, `removeSuffix`, `removePrefix`, `removeSurrounding`）
- [x] MIGRATION-TEXT-003: String パディング・繰り返し関数を Kotlin source に移行する（`padStart`, `padEnd`, `repeat`, `reversed`）
- [x] MIGRATION-TEXT-004: String 分割・結合関数を Kotlin source に移行する（`split`, `splitToSequence`, `joinToString`, `chunked`, `windowed`, `zipWithNext`, `zip`）
- [ ] MIGRATION-TEXT-005: String 大文字小文字・ロケール関数を Kotlin source に移行する（`lowercase`, `uppercase`, `capitalize`, `replaceFirstChar`, locale 版）
- [ ] MIGRATION-TEXT-006: String インデント・フォーマット関数を Kotlin source に移行する（`trimIndent`, `trimMargin`, `prependIndent`, `replaceIndent`, `format`）
- [ ] MIGRATION-TEXT-007: String encode/decode 関数を Kotlin source に移行する（`encodeToByteArray`, `decodeToString`, charset 版含む）
- [ ] MIGRATION-TEXT-008: String HOF 関数を Kotlin source に移行する（`filter`, `filterNot`, `filterIndexed`, `map`, `mapIndexed`, `mapNotNull`, `flatMap`, `fold`, `reduce`, `scan` 等）
- [x] MIGRATION-TEXT-009: String commonPrefix/Suffix・比較関数を Kotlin source に移行する（`commonPrefixWith`, `commonSuffixWith`, ignoreCase 版含む）

### Phase M2: kotlin.text StringBuilder
> 移行元: `Sources/Runtime/RuntimeStringBuilder.swift` (29 @_cdecl)
> 移行先: `Stdlib/kotlin/text/StringBuilder.kt`

- [ ] MIGRATION-SB-001: `StringBuilder` クラス API を Kotlin source に移行する（`append`, `appendLine`, `insert`, `delete`, `replace`, `toString`, `clear`, `length`, `capacity`）

### Phase M3: kotlin.collections ファクトリ・HOF
> 移行元: `Sources/Runtime/RuntimeCollectionHOF.swift` (166), `RuntimeCollectionHOFArray.swift` (27), `RuntimeCollectionHOFGrouping.swift` (11), `RuntimeCollectionHOFMaxMin.swift` (26), `RuntimeCollections.swift` (85)
> 移行先: `Stdlib/kotlin/collections/`

- [ ] MIGRATION-COL-001: Collection ファクトリ関数を Kotlin source に移行する（`listOf`, `mutableListOf`, `setOf`, `mutableSetOf`, `mapOf`, `mutableMapOf`, `emptyList`, `emptySet`, `emptyMap`）
- [ ] MIGRATION-COL-002: List 変換 HOF を Kotlin source に移行する（`map`, `mapIndexed`, `mapNotNull`, `flatMap`, `flatten`）
- [ ] MIGRATION-COL-003: List フィルタ HOF を Kotlin source に移行する（`filter`, `filterNot`, `filterNotNull`, `filterIndexed`, `filterIsInstance`）
- [ ] MIGRATION-COL-004: List 集約 HOF を Kotlin source に移行する（`fold`, `foldRight`, `reduce`, `reduceOrNull`, `scan`, `runningFold`）
- [ ] MIGRATION-COL-005: List 検索 HOF を Kotlin source に移行する（`first`, `firstOrNull`, `last`, `lastOrNull`, `single`, `singleOrNull`, `find`, `findLast`, `indexOf`, `indexOfFirst`, `indexOfLast`）
- [ ] MIGRATION-COL-006: List ソート・比較 HOF を Kotlin source に移行する（`sorted`, `sortedBy`, `sortedByDescending`, `sortedWith`, `reversed`, `shuffled`）
- [ ] MIGRATION-COL-007: List グルーピング・関連付け HOF を Kotlin source に移行する（`groupBy`, `groupByTo`, `associate`, `associateBy`, `associateWith`, `partition`）
- [ ] MIGRATION-COL-008: List 集計 HOF を Kotlin source に移行する（`count`, `any`, `all`, `none`, `maxByOrNull`, `minByOrNull`, `maxWith`, `minWith`, `sumOf`）
- [ ] MIGRATION-COL-009: List ウィンドウ・チャンク HOF を Kotlin source に移行する（`chunked`, `windowed`, `zipWithNext`, `zip`, `withIndex`）
- [ ] MIGRATION-COL-010: List 部分取得 HOF を Kotlin source に移行する（`take`, `takeLast`, `takeWhile`, `takeLastWhile`, `drop`, `dropLast`, `dropWhile`, `dropLastWhile`, `distinct`, `distinctBy`）
- [ ] MIGRATION-COL-011: List ビルダー関数を Kotlin source に移行する（`buildList`, `buildSet`, `buildMap`）
- [ ] MIGRATION-COL-012: Map HOF を Kotlin source に移行する（`map.filter`, `filterKeys`, `filterValues`, `mapKeys`, `mapValues`, `mapNotNull`, `flatMap`, `forEach`, `getOrElse`, `getOrDefault`）
- [ ] MIGRATION-COL-013: Set HOF を Kotlin source に移行する（`set.filter`, `map`, `flatMap`, `forEach`, `sorted`, `first`, `last`, `count`, `any`, `all`, `none`）

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
- [ ] CLEANUP-STUB-001: `kk_js_array_toArray` stub削除
- [ ] CLEANUP-STUB-002: `kk_js_array_get` stub削除
- [ ] CLEANUP-STUB-003: `kk_js_array_set` stub削除
- [ ] CLEANUP-STUB-004: `kk_js_array_create` stub削除
- [ ] CLEANUP-STUB-005: `kk_js_array_toList` stub削除
- [ ] CLEANUP-STUB-006: `kk_js_array_toMutableList` stub削除
#### JS Map関連stub
- [ ] CLEANUP-STUB-007: `kk_js_map_toMap` stub削除
- [ ] CLEANUP-STUB-008: `kk_js_map_toMutableMap` stub削除
#### JS Set関連stub
- [ ] CLEANUP-STUB-009: `kk_js_set_toSet` stub削除
- [ ] CLEANUP-STUB-010: `kk_js_set_toMutableSet` stub削除
#### JS型変換関連stub
- [ ] CLEANUP-STUB-011: `kk_js_bigint_toLong` stub削除
- [ ] CLEANUP-STUB-012: `kk_js_number_toDouble` stub削除
- [ ] CLEANUP-STUB-013: `kk_js_number_toInt` stub削除
- [ ] CLEANUP-STUB-014: `kk_js_boolean_toBoolean` stub削除
- [ ] CLEANUP-STUB-015: `kk_js_reference_get` stub削除
#### Wasm Export stub
- [ ] CLEANUP-STUB-016: Wasm Export stub削除（`HeaderHelpers+SyntheticWasmExportStubs.swift`）
#### Wasm Import stub
- [ ] CLEANUP-STUB-017: Wasm Import stub削除（`HeaderHelpers+SyntheticWasmImportStubs.swift`）
#### Wasm Unsafe Annotation stub
- [ ] CLEANUP-STUB-018: Wasm Unsafe Annotation stub削除（`HeaderHelpers+SyntheticWasmUnsafeAnnotationStubs.swift`）
#### Wasm Unsafe Memory Allocator stub
- [ ] CLEANUP-STUB-019: Wasm Unsafe Memory Allocator stub削除（`HeaderHelpers+SyntheticWasmUnsafeMemoryAllocatorStubs.swift`）
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
- [ ] CLEANUP-STUB-027: `kk_java_atomic_ref_asKotlinAtomic` stub削除（`HeaderHelpers+SyntheticAtomicStubs.swift`, `RuntimeAtomic.swift`実装も削除）
- [ ] CLEANUP-STUB-028: `kk_java_atomic_int_array_asKotlinAtomicArray` stub削除（`HeaderHelpers+SyntheticAtomicStubs.swift`, `RuntimeAtomic.swift`実装も削除）
- [ ] CLEANUP-STUB-029: `kk_java_atomic_long_array_asKotlinAtomicArray` stub削除（`HeaderHelpers+SyntheticAtomicStubs.swift`, `RuntimeAtomic.swift`実装も削除）
- [ ] CLEANUP-STUB-030: `kk_java_atomic_ref_array_asKotlinAtomicArray` stub削除（`HeaderHelpers+SyntheticAtomicStubs.swift`, `RuntimeAtomic.swift`実装も削除）
#### JVM Random相互運用stub
- [ ] CLEANUP-STUB-031: `kk_java_random_new` stub削除（`HeaderHelpers+SyntheticRandomStubs.swift`, `RuntimeRandom.swift`実装も削除）
- [ ] CLEANUP-STUB-032: `kk_java_random_new_seed` stub削除（`HeaderHelpers+SyntheticRandomStubs.swift`, `RuntimeRandom.swift`実装も削除）
#### JS/Wasm/JVM stub登録呼び出し削除
- [ ] CLEANUP-STUB-033: `HeaderHelpers+SyntheticPhase_PlatformAndJS.swift`の全呼び出し削除
- [ ] CLEANUP-STUB-034: `HeaderHelpers+SyntheticPhase_ExtendedStdlib.swift`のJS/Wasm/JVM関連呼び出し削除
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
- [ ] CLEANUP-STUB-044: JS Module stub削除（`HeaderHelpers+SyntheticJsModuleStubs.swift`）
- [ ] CLEANUP-STUB-045: JS Name stub削除（`HeaderHelpers+SyntheticJsNameStubs.swift`）
- [ ] CLEANUP-STUB-046: JS NonModule stub削除（`HeaderHelpers+SyntheticJsNonModuleStubs.swift`）
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
- [ ] CLEANUP-STUB-057: JS Qualifier stub削除（`HeaderHelpers+SyntheticJsQualifierStubs.swift`）
- [ ] CLEANUP-STUB-058: JS BigIntInterop stub削除（`HeaderHelpers+SyntheticJsBigIntInteropStubs.swift`）
- [ ] CLEANUP-STUB-059: JS NumberInterop stub削除（`HeaderHelpers+SyntheticJsNumberInteropStubs.swift`）
- [ ] CLEANUP-STUB-060: JS ReferenceInterop stub削除（`HeaderHelpers+SyntheticJsReferenceInteropStubs.swift`）
- [ ] CLEANUP-STUB-061: JS IntNumberInterop stub削除（`HeaderHelpers+SyntheticJsIntNumberInteropStubs.swift`）
- [ ] CLEANUP-STUB-062: JS ArrayInterop stub削除（`HeaderHelpers+SyntheticJsArrayInteropStubs.swift`）
- [ ] CLEANUP-STUB-063: JS PrimitiveWrappers stub削除（`HeaderHelpers+SyntheticJsPrimitiveWrappers.swift`）
- [x] CLEANUP-STUB-064: JS CollectionsArray stub削除（`HeaderHelpers+SyntheticJsCollectionsArrayStubs.swift`）
- [ ] CLEANUP-STUB-065: JS CollectionsMap stub削除（`HeaderHelpers+SyntheticJsCollectionsMapStubs.swift`）
- [ ] CLEANUP-STUB-066: JS CollectionsSet stub削除（`HeaderHelpers+SyntheticJsCollectionsSetStubs.swift`）
- [ ] CLEANUP-STUB-067: JS CollectionsReadonlyArray stub削除（`HeaderHelpers+SyntheticJsCollectionsReadonlyArrayStubs.swift`）
- [ ] CLEANUP-STUB-068: JS CollectionsReadonlySet stub削除（`HeaderHelpers+SyntheticJsCollectionsReadonlySetStubs.swift`）
- [ ] CLEANUP-STUB-069: JS CollectionsReadonlyMap stub削除（`HeaderHelpers+SyntheticJsCollectionsReadonlyMapToMapStubs.swift`）
- [ ] CLEANUP-STUB-070: JS Dynamic stub削除（`HeaderHelpers+SyntheticJsDynamicStubs.swift`）
- [ ] CLEANUP-STUB-071: JS Any stub削除（`HeaderHelpers+SyntheticJsAnyStubs.swift`）
- [ ] CLEANUP-STUB-072: JS Fun stub削除（`HeaderHelpers+SyntheticJsFunStubs.swift`）
- [ ] CLEANUP-STUB-073: JS Export stub削除（`HeaderHelpers+SyntheticJsExportStubs.swift`）
- [ ] CLEANUP-STUB-074: JS FileName stub削除（`HeaderHelpers+SyntheticJsFileNameStubs.swift`）
- [ ] CLEANUP-STUB-075: JS BigIntToLong stub削除（`HeaderHelpers+SyntheticJsBigIntToLongStubs.swift`）
- [ ] CLEANUP-STUB-076: JS BigInt stub削除（`HeaderHelpers+SyntheticJsBigIntStubs.swift`）
- [ ] CLEANUP-STUB-077: JS Boolean stub削除（`HeaderHelpers+SyntheticJsBooleanStubs.swift`）
- [ ] CLEANUP-STUB-078: JS Number stub削除（`HeaderHelpers+SyntheticJsNumberStubs.swift`）
- [ ] CLEANUP-STUB-079: JS Reference stub削除（`HeaderHelpers+SyntheticJsReferenceStubs.swift`）
- [ ] CLEANUP-STUB-080: JS RegExp stub削除（`HeaderHelpers+SyntheticJsRegExpStubs.swift`）
- [ ] CLEANUP-STUB-081: JS Stubs（メイン）削除（`HeaderHelpers+SyntheticJsStubs.swift`）
- [ ] CLEANUP-STUB-082: JVM AnnotationProperty stub削除（`HeaderHelpers+SyntheticJvmAnnotationPropertyStubs.swift`）
- [ ] CLEANUP-STUB-083: JVM Reflect stub削除（`HeaderHelpers+SyntheticJvmReflectStubs.swift`）
- [ ] CLEANUP-STUB-084: JVM Metaprog stub削除（`HeaderHelpers+SyntheticMetaprogStubs.swift`）
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
- [x] TEST-TIME-020: `kotlin.time` の Duration Long 受信ファクトリの実行テストを追加する。`from_days_long`（`5L.days`）/ `from_hours_long`（`5L.hours`）/ `from_minutes_long`（`5L.minutes`）/ `from_microseconds_long`（`5L.microseconds`）は実装ありだが実行テストなし。**注意**: `from_seconds_long` / `from_milliseconds_long` / `from_nanoseconds_long` は `CodegenBackendIntegrationTests+StableDurationEdgeCases.testDurationStableUnitExtensionPropertiesLong` でカバー済みのため対象外。カバー対象: 正常変換・`Long.MAX_VALUE` のオーバーフロー飽和（INFINITE）・負値・ゼロ
- [x] TEST-TIME-021: `kotlin.time` の Instant 変換の実行テストを追加する。`from_epoch_seconds`（`Instant.fromEpochSeconds(...)`）/ `to_epoch_millis`（`instant.toEpochMilliseconds()`）/ `to_foundation_date`（Foundation Date 変換）は `RuntimeTime.swift` に実装ありだが実行テストなし（`RuntimeInstantTests` は `from_epoch_millis`/`compare`/`elapsed`/`until` 等の別関数のみ）。カバー対象: epoch 往復・負の epoch（1970以前）・秒未満ナノ秒の保持・`fromEpochSeconds` の nanosecondAdjustment 引数
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
- [x] TEST-NUM-017: 数値境界の Kotlin parity（kotlinc 2.3.10 diff）を整備する。検証手段として `Scripts/diff_kotlinc.sh`（実 kotlinc 2.3.10）と `Tests/CompilerCoreTests/Codegen/CodegenBackendIntegrationTests+NumericBoundaries.swift` を使用。**一致を確認して固定済み**: 縮約変換（`Scripts/diff_cases/numeric_conversion_truncation.kt`）、浮動小数点→整数の境界/NaN/Inf（`float_to_int_boundaries.kt`）、Char 算術の基本（`char_arithmetic_basics.kt`）、unsigned companion 定数（`unsigned_companion_constants.kt`、PARITY-NUM-002 で修正）。**PARITY-NUM-001 修正により全 4 ケース有効化済み**: `integer_overflow_wraparound.kt` / `shift_amount_masking.kt` / `unsigned_arithmetic_overflow.kt` / `int_to_char_truncation.kt`（DIFF_IGNORE 解除）

## Kotlin 挙動 parity（kotlinc 2.3.10 比較で発見した差分）

> `Scripts/diff_kotlinc.sh` を実 kotlinc 2.3.10（Swift 6.2 + LLVM 18）で実行して検出。`// KSWIFTK_DIFF_IGNORE` ケースは `--force-run-skipped` で再現可能。

- [ ] PARITY-NUM-001: Int/Long/UInt の 32/64bit オーバーフロー・シフトが未実装（**重大・アーキテクチャ**）。native backend が全整数を i64 で表現し、Int(32bit) の演算結果を切り詰めず、シフト量もマスクしない（Int は `& 31`、Long は `& 63`）。
  - 症状: `Int.MAX_VALUE + 1` → `2147483648`（正 `-2147483648`）、`100000 * 100000` → `10000000000`（正 `1410065408`）、`1 shl 32` → `4294967296`（正 `1`）、`1 shl 31` → `2147483648`（正 `-2147483648`）、`1 shl -1` → `null`（範囲外シフトは LLVM 上 UB）、`UInt.MAX_VALUE + 1u` → `4294967296`（正 `0`）、`65601.toChar().code` → `65601`（正 `65`）。
  - 原因: `Sources/CompilerCore/Codegen/NativeEmitter+EmissionConstants.swift`（`kk_op_add`/`mul`/`shl`/`shr`/`ushr` 等が i64 のまま）と `NativeEmitter+FunctionEmission.swift` の `.binary` 経路。型(Int/Long)は KIR `exprTypes` にあるが emitter が TypeSystem を持たないため、型別 callee の分割か KIR 段での truncation/mask 挿入が必要（定数畳み込み経路も同様に未対応）。Byte/Short/Char/unsigned 縮約にも波及。
  - 再現: `Scripts/diff_cases/{integer_overflow_wraparound,shift_amount_masking,unsigned_arithmetic_overflow,int_to_char_truncation}.kt`。
- [x] PARITY-SEMA-003: 完全修飾 `kotlin.math.abs(x)` が解決できない（`KSWIFTK-SEMA-0002`/`0022`）。`tryInferFQNPackageTopLevelCall` を `CallTypeChecker+MemberCallInferenceContext.swift` に追加し、レシーバー型推論前にドット連鎖を FQN として照合・オーバーロード解決する経路を実装。
- [x] PARITY-NUM-001: Int/Long/UInt の 32/64bit オーバーフロー・シフトを修正。`IntegerNarrowingPass` に UInt → `kk_uint_narrow`（`& 0xFFFFFFFF`）分岐を追加、`CallLowerer+LegacyMemberLikeCalls` の `Int.toChar()` を identity から `kk_int_to_char` 呼び出しに修正。全 4 diff_case が kotlinc 2.3.10 と一致。
- [x] PARITY-NUM-001: Int/Long/UInt の 32/64bit オーバーフロー・シフトを修正。`IntegerNarrowingPass` に UInt → `kk_uint_narrow`（`& 0xFFFFFFFF`）分岐を追加、`CallLowerer+LegacyMemberLikeCalls` の `Int.toChar()` を identity から `kk_int_to_char` 呼び出しに修正。全 4 diff_case が kotlinc 2.3.10 と一致。
- [x] PARITY-SEMA-003: 完全修飾 `kotlin.math.abs(x)` が解決できない（`KSWIFTK-SEMA-0002`/`0022`）。`import kotlin.math.abs` 経由は可。`kotlin.math.*` トップレベル関数を完全修飾名で呼ぶ経路の名前解決ギャップ。
- [x] PARITY-PARSE-004: ソフトキーワード `by` をローカル変数名に使えない（`KSWIFTK-SEMA-0013`）。kotlinc は受理。`val by = ...` のような識別子としての `by` をパーサ/sema が拒否。
- [x] PARITY-CODEGEN-005: `Char.compareTo(Char)` がリンクエラー（`undefined reference to 'compareTo'`）。`'Z'.compareTo('A')` で発生。Char の `compareTo` メンバ呼び出しの lowering/ランタイムシンボル欠落。
- [x] TEST-TEXT-017: `String` の数値/真偽パース関数の実行テストを追加する。`toByte` / `toByteOrNull` / `toShort` / `toShortOrNull` / `toLong` / `toLongOrNull` / `toFloat` / `toFloatOrNull` / `toBoolean` / `toBooleanStrict` / `toBooleanStrictOrNull` は `RuntimeStringStdlib.swift` に実装ありだが実行テストが皆無（`toInt`/`toIntOrNull`/`toDouble` は既存、`RuntimeNumberFormatTests` はロケールフォーマッタのみで別物）。カバー対象: 正常パース・オーバーフロー（非 OrNull は `NumberFormatException`、OrNull は `null`）・不正形式・前後空白・符号・`toBooleanStrict` の大小文字厳密性
- [x] TEST-CHAR-019: `Char` 関数の実行テストを追加する。`isISOControl` / `plus`(Char+Int) / `minus`(Char-Char, Char-Int) / `get`（`String[i]`）/ `range_forEach`（`('a'..'z').forEach`）は実装ありだが実行テストなし（`RuntimeCharTests` は `uppercase`/`digitToInt`/`isLetter` 等の別関数、算術は AST 型確認と Golden のみで実行せず）。カバー対象: ISO制御文字の境界（U+001F/U+007F 等）・`plus`/`minus` のオーバーフロー・降順 CharRange・空 CharRange
- [x] TEST-TEXT-018: `String` の高階関数の実行テストを追加する。`filter` / `filterNot` / `filterIndexed` / `map` / `mapIndexed` / `mapNotNull` / `all` / `any` / `none` / `count` / `find` / `findLast` / `first` / `firstOrNull` / `last` / `lastOrNull` / `single` / `singleOrNull` / `partition` / `takeWhile` / `dropWhile` は実装ありだが Sema 解決テストのみで実行テストなし（`RuntimeStringHOFTests` は `firstNotNullOf`/`reduceRight*` 等の別関数のみ）。カバー対象: 空文字列・単一文字・全一致/不一致・`first`/`last`/`single` の空で例外・`singleOrNull` の複数要素で `null`・`partition` の `Pair<String,String>`

## 仕様準拠監査（Spec Conformance Audit）

Kotlin 公式仕様 / stdlib ドキュメントを基準に挙動を照合し、差異を記録・修正する継続タスク。

### 方法論
- 公式に文書化された挙動を真とし、二層で検証する:
  1. **doc 由来ユニットテスト**（kotlinc 非依存・CI 強制）: 期待値を直接アサート。例: `Tests/RuntimeTests/RuntimeFloatingPointToStringTests.swift`。
  2. **kotlinc 比較 diff ケース**: `Scripts/diff_cases/num_*.kt` を `Scripts/diff_kotlinc.sh` で本物の kotlinc(2.3.10) と突き合わせる。
- 採番は `SPEC-NUM-{NUMBER}`。修正できない大規模/横断要因は再現 diff ケースを `// SKIP-DIFF` で残し追跡する（修正後にマーカーを外せば回帰テストになる）。

### 数値・プリミティブ型（第1バッチ）
- [x] SPEC-NUM-0001: `Int`/`Short`/`Byte` の算術・シフトが 64bit 幅で計算され 32/16/8bit へ切り詰められない。符号付きオーバーフローがラップせず、`Int.MAX_VALUE + 1`→`2147483648`（正: `-2147483648`）、`1 shl 32`→`4294967296`（正: シフト量マスクで `1`）等。`IntegerNarrowingPass`（KIR 段で `kk_int_narrow` / `kk_uint_narrow` 挿入）と型別シフト callee（`kk_op_ishl` 等）で修正済み。再現: `Scripts/diff_cases/num_int_overflow.kt`。
- [ ] SPEC-NUM-0002: 整数のゼロ除算・剰余が catch 可能な `ArithmeticException`（"/ by zero"）を投げず、ハードウェア SIGFPE でプロセスが異常終了する（catch 不能）。codegen で除数のゼロチェックを挿入する必要あり。浮動小数のゼロ除算（Infinity/NaN）は正しい。再現: `Scripts/diff_cases/num_div_by_zero.kt`（SKIP-DIFF）。
- [ ] SPEC-NUM-0003: `Double`/`Float` の関係演算子（`<` `<=` `>` `>=`）が IEEE-754 比較（NaN は常に false）ではなく `Comparable.compareTo`（全順序、NaN 最大）経由になり、`1.0 < Double.NaN`→`true`（正: `false`）等。`compareTo` 束縛を外すと OperatorLoweringPass が被演算子の Double ランクを検出できず（`arena.exprType` が nil）整数比較 `kk_op_lt` に落ち、負の double 比較を壊すため、KIR 型伝播の改善（または専用 IEEE 比較 desugar）とセットで対応が必要。再現: `Scripts/diff_cases/num_nan_comparison.kt`（SKIP-DIFF）。
- [ ] SPEC-NUM-0006: `Double.MIN_VALUE`/`Float.MIN_VALUE` の最短10進表現が `java.lang.*.toString` と異なる（Kotlin: `4.9E-324`/`1.4E-45`、kswiftk: `5.0E-324`/`1.0E-45`）。Swift の最短表現と Java の FloatingDecimal の差。subnormal 端の完全一致は別途。再現: `Scripts/diff_cases/num_float_min_value.kt`（SKIP-DIFF）。
- [ ] SPEC-NUM-0007: 符号なし型のコンパニオン定数 `UInt`/`ULong`/`UByte`/`UShort.MAX_VALUE`/`MIN_VALUE` が未解決（`KSWIFTK-SEMA-0024`）。加えて `UInt.toByte()` や `String.toUByteOrNull()` 等の一部変換/パーサが未配線。再現: `Scripts/diff_cases/num_unsigned_limits.kt`（SKIP-DIFF）。
- [x] SPEC-NUM-0008: プリミティブ `Double`/`Float` への明示メンバ呼び出しの欠落。`x.compareTo(y)` がリンクエラー（`undefined reference to 'compareTo'`）、`(-0.0).toString()` が `"null"` を返す。また関数の戻り値として返した `-0.0` が呼び出し側の `println` で `0.0` に化ける（戻り値経路で符号消失）。修正: `kk_any_to_string` で tag 5/6 を null sentinel チェック前に処理（null 衝突解消）、`runtimeFormatFloatingPoint` に `-0.0` 明示ガード追加、Float.compareTo テスト追加。再現テスト: `CodegenBackendIntegrationTests+NegativeZeroMemberCalls`、diff_case: `num_negative_zero_member_calls.kt`。

## 全体リファクタリング計画（RF0–RF8）

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
