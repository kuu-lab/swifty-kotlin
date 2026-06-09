# Kotlin Compiler Remaining Tasks

最終更新: 2026-05-31

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
- [ ] STDLIB-004: `Array` / primitive array の生成・変換・境界挙動を整理する
- [x] STDLIB-GAP-PH1: ギャップ表の `kotlin` / `kotlin.text` / `Array` 周辺の未対応を潰す

### Phase 2: コレクション・Sequence・Range
- [~] STDLIB-022: range / progression / unsigned range の網羅性を上げる（LongRange `firstOrNull` / `lastOrNull` runtime 済み）

#### kotlin.collections 関数の実装（D-Z）
- [x] STDLIB-COL-FN-073: `firstNotNullOfOrNull` 関数の実装
- [ ] STDLIB-COL-FN-074: `firstOrNull` 関数の実装
- [x] STDLIB-COL-FN-075: `flatMap` 関数の実装
- [ ] STDLIB-COL-FN-073: `firstNotNullOfOrNull` 関数の実装
- [x] STDLIB-COL-FN-074: `firstOrNull` 関数の実装
- [ ] STDLIB-COL-FN-075: `flatMap` 関数の実装

### Phase 3: I/O・パス・時間・並行（common）
- [~] STDLIB-GAP-PH3: `kotlin.io`（common） / `kotlin.time` / `kotlin.concurrent` / `kotlin.concurrent.atomics` の未対応を潰す

#### kotlin.concurrent 型の実装
- [ ] STDLIB-030: `kotlin.io` common 範囲の file / buffered / `use` を仕様単位で締める

#### kotlin.concurrent 関数の実装

#### kotlin.concurrent.atomics 型の実装

#### kotlin.contracts 型の実装

#### kotlin.coroutines.cancellation 関数の実装

#### kotlin.io 型の実装
- [x] STDLIB-IO-TYPE-004: `FileTreeWalk` クラスの実装

#### kotlin.io プロパティの実装
- [x] STDLIB-IO-TYPE-007: `OnErrorAction` enum の実装

#### kotlin.io プロパティの実装
- [x] STDLIB-IO-PROP-003: `invariantSeparatorsPath` 拡張プロパティの実装
- [ ] STDLIB-IO-PROP-003: `invariantSeparatorsPath` 拡張プロパティの実装
- [ ] STDLIB-IO-TYPE-007: `OnErrorAction` enum の実装
- [x] STDLIB-IO-TYPE-007: `OnErrorAction` enum の実装

#### kotlin.io プロパティの実装
- [x] STDLIB-IO-PROP-003: `invariantSeparatorsPath` 拡張プロパティの実装
- [x] STDLIB-IO-PROP-004: `isRooted` 拡張プロパティの実装

#### kotlin.io 関数の実装
- [x] STDLIB-IO-FN-001: `appendBytes` 関数の実装
- [x] STDLIB-IO-FN-009: `bufferedWriter` 関数の実装（OutputStream版）
- [x] STDLIB-IO-FN-010: `bufferedWriter` 関数の実装（File版）
- [x] STDLIB-IO-FN-011: `byteInputStream` 関数の実装
- [x] STDLIB-IO-FN-012: `copyRecursively` 関数の実装
- [x] STDLIB-IO-FN-007: `bufferedReader` 関数の実装（InputStream版）
- [x] STDLIB-IO-FN-014: `copyTo` 関数の実装（Reader版）
- [x] STDLIB-IO-FN-016: `forEachBlock` 関数の実装
- [x] STDLIB-IO-FN-020: `inputStream` 関数の実装（ByteArray版）
- [x] STDLIB-IO-FN-017: `forEachLine` 関数の実装（Reader版）
- [x] STDLIB-IO-FN-021: `inputStream` 関数の実装（ByteArray範囲版）
- [x] STDLIB-IO-FN-024: `normalize` 関数の実装
- [x] STDLIB-IO-FN-029: `readBytes` 関数の実装（InputStream版）
- [x] STDLIB-IO-FN-033: `readText` 関数の実装（Reader版）
- [ ] STDLIB-IO-FN-009: `bufferedWriter` 関数の実装（OutputStream版）
- [ ] STDLIB-IO-FN-010: `bufferedWriter` 関数の実装（File版）
- [ ] STDLIB-IO-FN-011: `byteInputStream` 関数の実装
- [ ] STDLIB-IO-FN-012: `copyRecursively` 関数の実装
- [ ] STDLIB-IO-FN-007: `bufferedReader` 関数の実装（InputStream版）
- [ ] STDLIB-IO-FN-014: `copyTo` 関数の実装（Reader版）
- [ ] STDLIB-IO-FN-016: `forEachBlock` 関数の実装
- [ ] STDLIB-IO-FN-020: `inputStream` 関数の実装（ByteArray版）
- [ ] STDLIB-IO-FN-017: `forEachLine` 関数の実装（Reader版）
- [ ] STDLIB-IO-FN-021: `inputStream` 関数の実装（ByteArray範囲版）
- [ ] STDLIB-IO-FN-024: `normalize` 関数の実装
- [ ] STDLIB-IO-FN-029: `readBytes` 関数の実装（InputStream版）
- [ ] STDLIB-IO-FN-033: `readText` 関数の実装（Reader版）
- [ ] STDLIB-IO-FN-030: `readBytes` 関数の実装（URL版）
- [ ] STDLIB-IO-FN-038: `toRelativeString` 関数の実装
- [x] STDLIB-IO-FN-009: `bufferedWriter` 関数の実装（OutputStream版）
- [x] STDLIB-IO-FN-010: `bufferedWriter` 関数の実装（File版）
- [x] STDLIB-IO-FN-011: `byteInputStream` 関数の実装
- [x] STDLIB-IO-FN-012: `copyRecursively` 関数の実装
- [x] STDLIB-IO-FN-007: `bufferedReader` 関数の実装（InputStream版）
- [x] STDLIB-IO-FN-014: `copyTo` 関数の実装（Reader版）
- [x] STDLIB-IO-FN-016: `forEachBlock` 関数の実装
- [x] STDLIB-IO-FN-020: `inputStream` 関数の実装（ByteArray版）
- [x] STDLIB-IO-FN-017: `forEachLine` 関数の実装（Reader版）
- [x] STDLIB-IO-FN-021: `inputStream` 関数の実装（ByteArray範囲版）
- [x] STDLIB-IO-FN-024: `normalize` 関数の実装
- [x] STDLIB-IO-FN-029: `readBytes` 関数の実装（InputStream版）
- [x] STDLIB-IO-FN-033: `readText` 関数の実装（Reader版）
- [x] STDLIB-IO-FN-030: `readBytes` 関数の実装（URL版）
- [x] STDLIB-IO-FN-038: `toRelativeString` 関数の実装

#### kotlin.io.encoding 型の実装

#### kotlin.io.path プロパティの実装

#### kotlin.io.path 関数の実装
- [x] STDLIB-IO-FN-040: `useLines` 関数の実装（Reader版）

- [ ] STDLIB-IO-PATH-FN-011: `createSymbolicLinkPointingTo` 関数の実装
- [ ] STDLIB-IO-PATH-FN-018: `fileVisitor` 関数の実装
- [ ] STDLIB-IO-PATH-FN-023: `getOwner` 関数の実装
- [ ] STDLIB-IO-PATH-FN-030: `readAttributes` 関数の実装
- [ ] STDLIB-IO-PATH-FN-028: `outputStream` 関数の実装
- [ ] STDLIB-IO-PATH-FN-019: `forEachDirectoryEntry` 関数の実装
- [ ] STDLIB-IO-PATH-FN-026: `moveTo` 関数の実装
- [ ] STDLIB-IO-PATH-FN-032: `setAttribute` 関数の実装
- [ ] STDLIB-IO-PATH-FN-037: `useDirectoryEntries` 関数の実装
- [ ] STDLIB-IO-PATH-FN-038: `useLines` 関数の実装
- [ ] STDLIB-IO-PATH-FN-039: `walk` 関数の実装
- [ ] STDLIB-IO-PATH-FN-040: `writeLines` 関数の実装（Iterable版）
- [ ] STDLIB-IO-PATH-FN-042: `writer` 関数の実装
#### kotlin.reflect 型の実装
- [ ] STDLIB-REFLECT-TYPE-010: `KMutableProperty0` インターフェースの実装
- [ ] STDLIB-REFLECT-TYPE-013: `KParameter` インターフェースの実装

#### kotlin.reflect プロパティの実装

#### kotlin.reflect 関数の実装

#### kotlin.sequences 型の実装

#### kotlin.sequences 関数の実装
- [ ] STDLIB-SEQ-FN-046: `groupBy` 関数の実装
- [ ] STDLIB-SEQ-FN-044: `forEach` 関数の実装
- [ ] STDLIB-SEQ-FN-047: `groupByTo` 関数の実装
- [ ] STDLIB-REFLECT-TYPE-009: `KMutableProperty` インターフェースの実装
- [ ] STDLIB-REFLECT-TYPE-015: `KProperty0` インターフェースの実装

- [ ] STDLIB-SEQ-FN-005: `associate` 関数の実装
- [ ] STDLIB-SEQ-FN-009: `associateWith` 関数の実装
- [ ] STDLIB-SEQ-FN-087: `plus` 関数の実装
#### kotlin.system 関数の実装
- [ ] STDLIB-SYSTEM-FN-001: `exitProcess` 関数の実装
- [ ] STDLIB-SYSTEM-FN-003: `getTimeMillis` 関数の実装
- [ ] STDLIB-SYSTEM-FN-005: `measureNanoTime` 関数の実装
- [ ] STDLIB-SYSTEM-FN-006: `measureTimeMicros` 関数の実装
- [ ] STDLIB-SYSTEM-FN-004: `getTimeNanos` 関数の実装
- [ ] STDLIB-SYSTEM-FN-007: `measureTimeMillis` 関数の実装

#### kotlin.text 型の実装
- [x] STDLIB-TEXT-TYPE-008: `MatchGroupCollection` インターフェースの実装
- [x] STDLIB-TEXT-TYPE-010: `MatchResult` インターフェースの実装

#### kotlin.text プロパティの実装
- [ ] STDLIB-TEXT-PROP-009: `isJavaIdentifierPart` 拡張プロパティの実装
- [x] STDLIB-TEXT-PROP-010: `isJavaIdentifierStart` 拡張プロパティの実装
- [x] STDLIB-TEXT-PROP-008: `isIdentifierIgnorable` 拡張プロパティの実装
- [x] STDLIB-TEXT-PROP-003: `directionality` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-015: `isSurrogate` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-016: `isTitleCase` 拡張プロパティの実装
- [ ] STDLIB-TEXT-PROP-017: `isUnicodeIdentifierPart` 拡張プロパティの実装

#### kotlin.text 関数の実装
- [ ] STDLIB-TEXT-FN-004: `appendLine` 関数の実装

- [ ] STDLIB-TEXT-FN-003: `append` 関数の実装
- [ ] STDLIB-TEXT-FN-005: `appendRange` 関数の実装
- [ ] STDLIB-TEXT-FN-008: `buildStringBuilder` 関数の実装
- [ ] STDLIB-TEXT-FN-006: `buildString` 関数の実装
- [ ] STDLIB-TEXT-FN-007: `buildStringAppend` 関数の実装
- [x] STDLIB-TEXT-FN-009: `capitalize` 関数の実装
- [ ] STDLIB-TEXT-FN-010: `codePointCount` 関数の実装
- [x] STDLIB-TEXT-FN-014: `encodeToByteArray` 関数の実装
- [ ] STDLIB-TEXT-FN-021: `indexOfAny` 関数の実装
- [ ] STDLIB-TEXT-FN-023: `indexOfLast` 関数の実装
- [ ] STDLIB-TEXT-FN-025: `insertRange` 関数の実装
- [ ] STDLIB-TEXT-FN-026: `intern` 関数の実装
- [ ] STDLIB-TEXT-FN-034: `lastIndexOf` 関数の実装
- [ ] STDLIB-TEXT-FN-033: `iterator` 関数の実装
- [ ] STDLIB-TEXT-FN-013: `decodeToString` 関数の実装
- [ ] STDLIB-TEXT-FN-016: `equals` 関数の実装
- [ ] STDLIB-TEXT-FN-019: `indent` 関数の実装
- [ ] STDLIB-TEXT-FN-022: `indexOfFirst` 関数の実装
- [ ] STDLIB-TEXT-FN-024: `insert` 関数の実装
- [ ] STDLIB-TEXT-FN-027: `isBlank` 関数の実装
- [ ] STDLIB-TEXT-FN-031: `isNullOrEmpty` 関数の実装
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
- [ ] STDLIB-TEXT-FN-055: `replace` 関数の実装
- [ ] STDLIB-TEXT-FN-056: `replaceAfter` 関数の実装
- [ ] STDLIB-TEXT-FN-058: `replaceBefore` 関数の実装
- [ ] STDLIB-TEXT-FN-060: `replaceFirst` 関数の実装
- [ ] STDLIB-TEXT-FN-062: `replaceRange` 関数の実装
- [ ] STDLIB-TEXT-FN-068: `slice` 関数の実装
- [ ] STDLIB-TEXT-FN-065: `setRange` 関数の実装
- [ ] STDLIB-TEXT-FN-067: `singleOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-070: `splitToSequence` 関数の実装
- [ ] STDLIB-TEXT-FN-072: `subSequence` 関数の実装
- [ ] STDLIB-TEXT-FN-074: `substringAfter` 関数の実装
- [ ] STDLIB-TEXT-FN-075: `substringAfterLast` 関数の実装
- [ ] STDLIB-TEXT-FN-077: `substringBeforeLast` 関数の実装
- [ ] STDLIB-TEXT-FN-079: `takeIf` 関数の実装
- [ ] STDLIB-TEXT-FN-081: `takeLastWhile` 関数の実装
- [ ] STDLIB-TEXT-FN-083: `toBigDecimal` 関数の実装
- [ ] STDLIB-TEXT-FN-085: `toBigInteger` 関数の実装
- [ ] STDLIB-TEXT-FN-086: `toBigIntegerOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-082: `takeWhile` 関数の実装
- [ ] STDLIB-TEXT-FN-084: `toBigDecimalOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-094: `toCollection` 関数の実装
- [ ] STDLIB-TEXT-FN-091: `toByteOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-095: `toDouble` 関数の実装
- [x] STDLIB-TEXT-FN-096: `toDoubleOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-101: `toList` 関数の実装
- [ ] STDLIB-TEXT-FN-104: `toMutableList` 関数の実装
- [ ] STDLIB-TEXT-FN-106: `toShort` 関数の実装
- [ ] STDLIB-TEXT-FN-108: `toSortedSet` 関数の実装
- [ ] STDLIB-TEXT-FN-088: `toBooleanStrict` 関数の実装
- [ ] STDLIB-TEXT-FN-089: `toBooleanStrictOrNull` 関数の実装
- [x] STDLIB-TEXT-FN-092: `toByteArray` 関数の実装
- [ ] STDLIB-TEXT-FN-101: `toList` 関数の実装
- [ ] STDLIB-TEXT-FN-104: `toMutableList` 関数の実装
- [ ] STDLIB-TEXT-FN-106: `toShort` 関数の実装
- [ ] STDLIB-TEXT-FN-108: `toSortedSet` 関数の実装
- [ ] STDLIB-TEXT-FN-088: `toBooleanStrict` 関数の実装
- [ ] STDLIB-TEXT-FN-089: `toBooleanStrictOrNull` 関数の実装
- [x] STDLIB-TEXT-FN-092: `toByteArray` 関数の実装
- [ ] STDLIB-TEXT-FN-096: `toDoubleOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-092: `toByteArray` 関数の実装
- [x] STDLIB-TEXT-FN-096: `toDoubleOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-098: `toFloatOrNull` 関数の実装
- [x] STDLIB-TEXT-FN-098: `toFloatOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-102: `toLong` 関数の実装
- [x] STDLIB-TEXT-FN-105: `toRegex` 関数の実装
- [ ] STDLIB-TEXT-FN-107: `toShortOrNull` 関数の実装
- [ ] STDLIB-TEXT-FN-115: `withIndex` 関数の実装
- [ ] STDLIB-TEXT-FN-116: `zip` 関数の実装

#### kotlin.time 型の実装
- [x] STDLIB-TIME-TYPE-005: `Duration` クラスの実装
- [ ] STDLIB-TIME-TYPE-007: `ExperimentalTime` アノテーションの実装
- [ ] STDLIB-TIME-TYPE-009: `TestTimeSource` クラスの実装
- [x] STDLIB-TIME-TYPE-010: `TimedValue` クラスの実装
- [x] STDLIB-TIME-TYPE-012: `TimeSource` インターフェースの実装

#### kotlin.time プロパティの実装
- [x] STDLIB-TIME-PROP-001: `isDistantFuture` 拡張プロパティの実装

#### kotlin.time 関数の実装
- [x] STDLIB-TIME-FN-002: `measureTime` 関数の実装
- [x] STDLIB-TIME-FN-001: `asClock` 関数の実装
- [x] STDLIB-TIME-FN-004: `times` 関数の実装
- [x] STDLIB-TIME-FN-005: `toDuration` 関数の実装
- [ ] STDLIB-TIME-FN-006: `toDurationUnit` 関数の実装
- [x] STDLIB-TIME-FN-008: `toJavaInstant` 関数の実装
- [x] STDLIB-TIME-FN-007: `toJavaDuration` 関数の実装
- [x] STDLIB-TIME-FN-009: `toJSDate` 関数の実装
- [x] STDLIB-TIME-FN-010: `toKotlinDuration` 関数の実装
- [ ] STDLIB-TIME-FN-012: `toTimeUnit` 関数の実装

#### kotlin.uuid 型の実装

#### kotlin.uuid 関数の実装
#### kotlin.uuid 関数の実装
- [ ] STDLIB-UUID-FN-002: `putUuid` 関数の実装
- [ ] STDLIB-UUID-FN-004: `toKotlinUuid` 関数の実装

### Phase 4: リフレクション・数値・テキスト・その他 stdlib
- [ ] STDLIB-REFLECT-067: `KClass` / metadata / メンバ introspection の残差を詰める
- [x] STDLIB-RANDOM-002: `kotlin.random` の sema / lowering を整える
- [ ] STDLIB-COMP-001: `kotlin.comparisons` の対象 API 一覧を固定
- [x] STDLIB-COMP-002: `Comparator` 合成の sema / lowering を整える
- [x] STDLIB-RANDOM-001: `kotlin.random` の対象 API 一覧を固定

#### kotlin.comparisons 関数の実装
- [x] STDLIB-COMP-FN-002: `compareByDescending` 関数の実装（selector版）
- [ ] STDLIB-COMP-FN-003: `compareValues` 関数の実装
- [x] STDLIB-COMP-FN-005: `maxOf` 関数の実装（Comparable版、2引数）
- [ ] STDLIB-COMP-FN-007: `maxOf` 関数の実装（Comparable版、vararg）
- [x] STDLIB-COMP-FN-009: `maxOf` 関数の実装（Byte版、3引数）
- [ ] STDLIB-COMP-FN-010: `maxOf` 関数の実装（Byte版、vararg）
- [ ] STDLIB-COMP-FN-014: `maxOf` 関数の実装（Float版、2引数）
- [ ] STDLIB-COMP-FN-012: `maxOf` 関数の実装（Double版、3引数）
- [ ] STDLIB-COMP-FN-015: `maxOf` 関数の実装（Float版、3引数）
- [ ] STDLIB-COMP-FN-011: `maxOf` 関数の実装（Double版、2引数）
- [ ] STDLIB-COMP-FN-017: `maxOf` 関数の実装（Int版、2引数）
- [ ] STDLIB-COMP-FN-020: `maxOf` 関数の実装（Long版、2引数）
- [ ] STDLIB-COMP-FN-022: `maxOf` 関数の実装（Long版、vararg）
- [ ] STDLIB-COMP-FN-024: `maxOf` 関数の実装（Short版、3引数）
- [ ] STDLIB-COMP-FN-028: `maxWithOrNull` 関数の実装
- [ ] STDLIB-COMP-FN-029: `minOf` 関数の実装（Comparable版、2引数）
- [ ] STDLIB-COMP-FN-030: `minOf` 関数の実装（Comparable版、3引数）
- [ ] STDLIB-COMP-FN-032: `minOf` 関数の実装（Byte版、2引数）
- [ ] STDLIB-COMP-FN-034: `minOf` 関数の実装（Byte版、vararg）
- [ ] STDLIB-COMP-FN-039: `minOf` 関数の実装（Float版、3引数）
- [ ] STDLIB-COMP-FN-035: `minOf` 関数の実装（Double版、2引数）
- [ ] STDLIB-COMP-FN-036: `minOf` 関数の実装（Double版、3引数）
- [ ] STDLIB-COMP-FN-038: `minOf` 関数の実装（Float版、2引数）
- [ ] STDLIB-COMP-FN-041: `minOf` 関数の実装（Int版、2引数）
- [ ] STDLIB-COMP-FN-043: `minOf` 関数の実装（Int版、vararg）
- [ ] STDLIB-COMP-FN-044: `minOf` 関数の実装（Long版、2引数）
- [ ] STDLIB-COMP-FN-046: `minOf` 関数の実装（Long版、vararg）
- [ ] STDLIB-COMP-FN-040: `minOf` 関数の実装（Float版、vararg）
- [ ] STDLIB-COMP-FN-051: `minOf` 関数の実装（UInt版）
- [ ] STDLIB-COMP-FN-052: `minOf` 関数の実装（ULong版）
- [ ] STDLIB-COMP-FN-050: `minOf` 関数の実装（UByte版）
- [ ] STDLIB-COMP-FN-062: `nullsLast` 関数の実装（Comparator版）
- [ ] STDLIB-COMP-FN-061: `nullsLast` 関数の実装（Comparable版）
- [ ] STDLIB-COMP-FN-053: `minOf` 関数の実装（UShort版）
- [ ] STDLIB-COMP-FN-055: `minWith` 関数の実装
- [ ] STDLIB-COMP-FN-059: `nullsFirst` 関数の実装（Comparable版）

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
- [ ] STDLIB-RANDOM-FN-024: `nextInt(range: IntRange)` 関数の実装（sema/ABI 配線済み・runtime `kk_random_nextInt_rangeObject` 未実装）
- [x] STDLIB-RANDOM-FN-025: `nextLong()` 関数の実装
- [x] STDLIB-RANDOM-FN-026: `nextLong(until: Long)` 関数の実装
- [x] STDLIB-RANDOM-FN-027: `nextLong(from: Long, until: Long)` 関数の実装
- [ ] STDLIB-RANDOM-FN-028: `nextLong(range: LongRange)` 関数の実装（sema/ABI 配線済み・runtime `kk_random_nextLong_rangeObject` 未実装）
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
- [ ] STDLIB-IO-PATH-FN-074: `Path.visitFileTree(maxDepth, followLinks, builderAction)` を追加する
- [ ] STDLIB-JS-COLLECTIONS-TYPE-003: `kotlin.js.collections.JsReadonlyArray<E>` external interface を追加する
- [ ] STDLIB-JS-COLLECTIONS-TYPE-004: `kotlin.js.collections.JsReadonlyMap<K, V>` external interface を追加する
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
- [ ] STDLIB-CINTEROP-FN-017: `Array<CPointer<T>?>.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-018: `ByteArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-024: `UByteArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-025: `UIntArray.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-028: `List<CPointer<T>?>.toCValues()` を追加する
- [ ] STDLIB-CINTEROP-FN-032: `CPointer<UShortVar>.toKString()` を追加する
- [ ] STDLIB-CINTEROP-FN-036: `CPointer<IntVar>.toKStringFromUtf32()` を追加する
- [ ] STDLIB-CINTEROP-FN-038: `CPointer<T>?.toLong()` を追加する
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

## ターゲット外バックログ（本体非追跡）
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
- [x] PARITY-SEMA-003: 完全修飾 `kotlin.math.abs(x)` が解決できない（`KSWIFTK-SEMA-0002`/`0022`）。`import kotlin.math.abs` 経由は可。`kotlin.math.*` トップレベル関数を完全修飾名で呼ぶ経路の名前解決ギャップ。
- [x] PARITY-NUM-001: Int/Long/UInt の 32/64bit オーバーフロー・シフトを修正。`IntegerNarrowingPass` に UInt → `kk_uint_narrow`（`& 0xFFFFFFFF`）分岐を追加、`CallLowerer+LegacyMemberLikeCalls` の `Int.toChar()` を identity から `kk_int_to_char` 呼び出しに修正。全 4 diff_case が kotlinc 2.3.10 と一致。
- [ ] PARITY-SEMA-003: 完全修飾 `kotlin.math.abs(x)` が解決できない（`KSWIFTK-SEMA-0002`/`0022`）。`import kotlin.math.abs` 経由は可。`kotlin.math.*` トップレベル関数を完全修飾名で呼ぶ経路の名前解決ギャップ。
- [x] PARITY-PARSE-004: ソフトキーワード `by` をローカル変数名に使えない（`KSWIFTK-SEMA-0013`）。kotlinc は受理。`val by = ...` のような識別子としての `by` をパーサ/sema が拒否。
- [x] PARITY-CODEGEN-005: `Char.compareTo(Char)` がリンクエラー（`undefined reference to 'compareTo'`）。`'Z'.compareTo('A')` で発生。Char の `compareTo` メンバ呼び出しの lowering/ランタイムシンボル欠落。
- [ ] TEST-TEXT-017: `String` の数値/真偽パース関数の実行テストを追加する。`toByte` / `toByteOrNull` / `toShort` / `toShortOrNull` / `toLong` / `toLongOrNull` / `toFloat` / `toFloatOrNull` / `toBoolean` / `toBooleanStrict` / `toBooleanStrictOrNull` は `RuntimeStringStdlib.swift` に実装ありだが実行テストが皆無（`toInt`/`toIntOrNull`/`toDouble` は既存、`RuntimeNumberFormatTests` はロケールフォーマッタのみで別物）。カバー対象: 正常パース・オーバーフロー（非 OrNull は `NumberFormatException`、OrNull は `null`）・不正形式・前後空白・符号・`toBooleanStrict` の大小文字厳密性
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
- [ ] SPEC-NUM-0001: `Int`/`Short`/`Byte` の算術・シフトが 64bit 幅で計算され 32/16/8bit へ切り詰められない。符号付きオーバーフローがラップせず、`Int.MAX_VALUE + 1`→`2147483648`（正: `-2147483648`）、`1 shl 32`→`4294967296`（正: シフト量マスクで `1`）等。実行時（関数引数）でも再現。codegen の整数幅の根本変更が必要。再現: `Scripts/diff_cases/num_int_overflow.kt`（SKIP-DIFF）。
- [ ] SPEC-NUM-0002: 整数のゼロ除算・剰余が catch 可能な `ArithmeticException`（"/ by zero"）を投げず、ハードウェア SIGFPE でプロセスが異常終了する（catch 不能）。codegen で除数のゼロチェックを挿入する必要あり。浮動小数のゼロ除算（Infinity/NaN）は正しい。再現: `Scripts/diff_cases/num_div_by_zero.kt`（SKIP-DIFF）。
- [ ] SPEC-NUM-0003: `Double`/`Float` の関係演算子（`<` `<=` `>` `>=`）が IEEE-754 比較（NaN は常に false）ではなく `Comparable.compareTo`（全順序、NaN 最大）経由になり、`1.0 < Double.NaN`→`true`（正: `false`）等。`compareTo` 束縛を外すと OperatorLoweringPass が被演算子の Double ランクを検出できず（`arena.exprType` が nil）整数比較 `kk_op_lt` に落ち、負の double 比較を壊すため、KIR 型伝播の改善（または専用 IEEE 比較 desugar）とセットで対応が必要。再現: `Scripts/diff_cases/num_nan_comparison.kt`（SKIP-DIFF）。
- [ ] SPEC-NUM-0006: `Double.MIN_VALUE`/`Float.MIN_VALUE` の最短10進表現が `java.lang.*.toString` と異なる（Kotlin: `4.9E-324`/`1.4E-45`、kswiftk: `5.0E-324`/`1.0E-45`）。Swift の最短表現と Java の FloatingDecimal の差。subnormal 端の完全一致は別途。再現: `Scripts/diff_cases/num_float_min_value.kt`（SKIP-DIFF）。
- [ ] SPEC-NUM-0007: 符号なし型のコンパニオン定数 `UInt`/`ULong`/`UByte`/`UShort.MAX_VALUE`/`MIN_VALUE` が未解決（`KSWIFTK-SEMA-0024`）。加えて `UInt.toByte()` や `String.toUByteOrNull()` 等の一部変換/パーサが未配線。再現: `Scripts/diff_cases/num_unsigned_limits.kt`（SKIP-DIFF）。
- [ ] SPEC-NUM-0008: プリミティブ `Double`/`Float` への明示メンバ呼び出しの欠落。`x.compareTo(y)` がリンクエラー（`undefined reference to 'compareTo'`）、`(-0.0).toString()` が `"null"` を返す。また関数の戻り値として返した `-0.0` が呼び出し側の `println` で `0.0` に化ける（戻り値経路で符号消失）。
