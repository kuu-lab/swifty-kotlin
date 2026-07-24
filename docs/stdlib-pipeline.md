# Stdlib ソースパイプライン設計 (RF-STDLIB-001)

Kotlin ソースで stdlib を実装するための設計メモ。TODO.md の Phase RF2（Stdlib ソースパイプライン基盤）
および M1–M17（モジュール別移行）の共通指針とする。

関連: [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) / [`docs/stdlib-fiction-audit.md`](stdlib-fiction-audit.md) /
[`docs/runtime-abi-external-link-validation-gaps.md`](runtime-abi-external-link-validation-gaps.md)

## 1. 目的とゴール

**ゴール**: stdlib の純ロジック（イテレーション・変換・比較・整形等）を Kotlin ソースとして実装し、
コンパイラ（Swift）側は「言語コア + ランタイムブリッジ」だけを持つ状態にする。

- `HeaderHelpers+Synthetic*`（規模は `Scripts/loc_report.sh` の `header_helpers_synthetic_total_lines` が正。
  2026-07-06 時点で 121 ファイル / 約8.2万行）を、(a) 削除・(b) Kotlin 移行・(c) 真の組込残留の
  3分類（§9）に沿って縮減する
- 挙動の正は **kotlinc 2.3.10**。`Scripts/diff_kotlinc.sh` を回帰 oracle とする
- ランタイム ABI 表面を「ユーザーコードから直接呼ばれる `kk_*`」から
  「stdlib Kotlin 層だけが呼ぶ `__kk_*` ブリッジ」へ縮小する

**非ゴール**:

- GC・メモリ管理・boxing・coroutine 機構・型メタデータ・プラットフォーム I/O の Kotlin 化（Swift ランタイムに残留）
- klib 相当のバイナリ配布形式の設計（§7 の測定結果が閾値を超えるまで着手しない）

## 2. 現状 (as-is)

stdlib 実装は 3 系統に分散している。

| 系統 | 場所 | 規模 | 状態 |
|---|---|---|---|
| 合成スタブ (Swift) | `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift` | 121 ファイル / ~8.2万行 (2026-07-06) | 主力。Sema 時に宣言登録し `kk_*` へ直結 |
| バンドル Kotlin ソース | `Sources/CompilerCore/Stdlib/kotlin/**/*.kt` | 25 ファイル / ~2,500 行 (2026-07-06) | `LoadSourcesPhase` が `__bundled_*.kt` として注入（RF-STDLIB-002 済） |
| インライン Kotlin 文字列 | `Sources/CompilerCore/Driver/BundledKotlinStdlib.swift` | ~550 行 | residual。§6 で廃止対象 |

補足:

- `LoadSourcesPhase.excludedBundledStdlibFiles` が「.kt は存在するが未配線」のファイルを
  除外している。除外リストは**移行の暫定措置**であり、最終状態では空にする
  （エントリ数は移行の進捗で単調減少する。現在値は `Driver/FrontendPhases.swift` の定義を参照）
- ルート `Stdlib/kotlin/` に死蔵 .kt が残っている（RF-HYG-003/004 参照）。§6 の単一ツリーへ統合する
- ランタイムは `@_cdecl` 関数 ~2,900 個（2026-07-06 実測。`grep -rhoE '@_cdecl\("kk_[a-zA-Z0-9_]+"\)' Sources/Runtime --include='*.swift' | sort -u | wc -l`）、署名は `RuntimeABISpec`（specVersion 管理）で宣言

## 3. あるべき姿 (to-be): 3層モデル

```
┌─────────────────────────────────────────────────────────┐
│ Layer 1: 純 Kotlin 層（stdlib の大半）                     │
│   HOF・String 操作・コレクションロジック・Range・Comparator 等│
│   Sources/CompilerCore/Stdlib/kotlin/**/*.kt              │
├─────────────────────────────────────────────────────────┤
│ Layer 2: ブリッジ宣言層（Kotlin で宣言・実体はランタイム）      │
│   @KsSymbolName("__kk_...") internal external fun ...     │
├─────────────────────────────────────────────────────────┤
│ Layer 3: Swift ランタイム層（最小コア）                      │
│   GC・alloc・boxing・coroutine 機構・型メタデータ・OS I/O     │
│   Sources/Runtime/ + RuntimeABISpec                       │
└─────────────────────────────────────────────────────────┘
```

責務の線引き（TODO.md「移行方針」を具体化）:

- **Kotlin のみ**: 他の stdlib API とブリッジ関数の組み合わせで書ける純ロジック全部
- **ブリッジ委譲**: OS/ハードウェアアクセス、メモリ表現に触る操作（文字列の生バイト、配列の生領域）、
  性能上ネイティブ実装が必須なホットパス（実測で判断）
- **Swift 残留（(c) 群）**: `Any`/プリミティブ型/`Nothing` など言語コアの組込宣言、GC・coroutine 機構

## 4. 読み込みフェーズ

`LoadSourcesPhase`（実装済・RF-STDLIB-002）の仕様を確定する。

1. ユーザー入力 (`ctx.options.inputs`) の検証後、`injectBundledStdlib` が
   `Bundle.module/Stdlib/**/*.kt` を列挙し、**相対パスの辞書順**で `sourceManager` に登録する
2. 登録パスは `__bundled_{modulePath}.kt` 形式。ユーザー入力と診断上区別でき、
   fileID 順序が決定的になる（golden 安定性の前提。§8）
3. `Sources/KSwiftKCLI/CLIParser.swift` の `--no-stdlib` で `CompilerOptions.includeStdlib` を false にし、注入全体を opt-out できる（コンパイラ自身のデバッグ用）
4. `excludedBundledStdlibFiles` は縦切り移行（§10）の完了ごとにエントリを削除し、最終的に撤廃する

**不変条件**: bundled ソースはユーザーソースより先に fileID を確保する。
ユーザーコードの有無で stdlib 側のシンボル ID・診断順序が変わってはならない。

## 5. 宣言の優先規則 (RF-STDLIB-003)

移行期間中は「Kotlin ソース由来の宣言」と「合成スタブ」が同一 API に対して共存しうる。
規則は一箇所（合成スタブ登録のエントリポイント）で実装する:

1. **Kotlin ソース > 合成スタブ**。bundled ソースに同シグネチャの宣言が存在する場合、
   合成スタブ登録をスキップする
2. スキップ判定は「レシーバ型 FQName + メンバ名 + アリティ」単位。オーバーロード集合の一部だけ
   Kotlin 化された状態を許容する（ただし縦切り PR では原則オーバーロード集合ごと移行する）
3. 双方が登録されてしまう二重定義はバグとして **warning 診断**（`KSWIFTK-SEMA-` 系コード採番）で検知する
4. スタブの存置は「Kotlin 版が配線されるまで」。配線 PR と同一 PR でスタブを削除する（§10）。
   長期共存させるフォールバックは作らない

`CallTypeChecker` / `CallLowerer` の名前文字列ベース特殊処理（RF4 系）も同じ優先規則に従う:
Kotlin ソースに実体がある呼び出しは通常の関数解決・KIR 展開に乗せ、専用 lowering を経由させない。

## 6. ソース配置とブリッジ宣言規約

### 配置

- **単一ツリー**: `Sources/CompilerCore/Stdlib/kotlin/`（`Bundle.module` で読める唯一の場所）。
  ルート `Stdlib/kotlin/` の死蔵ファイルは移行時にここへ統合し、ルート側は削除する
- **パッケージ構造は kotlin-stdlib 本家準拠**: `kotlin/text/`, `kotlin/collections/`,
  `kotlin/sequences/`, `kotlin/ranges/`, `kotlin/comparisons/`, ...
- **ファイル名も本家へ収斂させる**: 新規・移行時は本家のファイル名（例: `text/Strings.kt`,
  `collections/Collections.kt`）に寄せる。既存の機能スライス名（`ListFilterHOF.kt` 等)は
  当該モジュールの M フェーズ完了時に統合・リネームする
- `BundledKotlinStdlib.swift` のインライン文字列 4 本は対応する .kt ファイルへ移設し、廃止する

### ブリッジ宣言（external + 注釈）

ランタイム依存点は Kotlin ソース内で宣言する。Kotlin/Native の `@SymbolName` に倣い、
KSwiftK 内部注釈 `@KsSymbolName` を導入する:

```kotlin
package kotlin.text

@KsSymbolName("__kk_string_from_utf8")
internal external fun __stringFromUtf8(bytes: ByteArray, offset: Int, length: Int): String

public fun ByteArray.decodeToString(): String = __stringFromUtf8(this, 0, size)
```

規約:

- 注釈は `kotlin.internal` パッケージに置き、**stdlib ソース外（ユーザーコード）での使用はエラー**とする
- ブリッジ関数は `internal external fun`。シンボル名は `__kk_` prefix、宣言側 Kotlin 関数名は
  `__` prefix（ユーザー補完・公開 API 面に出さない）
- パーサは `external` 修飾子を受理済み（`KotlinParser+Utilities.swift`）。Sema は
  `@KsSymbolName` を externalLinkName として記録し、KIR/Codegen は既存の外部呼び出し経路をそのまま使う
- **ABI 突合を機械化する**: 「stdlib ソース中の全 `@KsSymbolName` 値が `RuntimeABISpec` に宣言され、
  型署名が一致する」ことをテストで enforcing にする。これにより
  `runtime-abi-external-link-validation-gaps.md` の検証ギャップは注釈⇔Spec の突合に一本化される

### `kk_*` → `__kk_*` の縮小

- 既存 `kk_*` 関数は、対応 API の Kotlin 移行時に (i) Kotlin 実装に置換して**削除**、または
  (ii) ブリッジとして**`__kk_*` へ改名・降格**（stdlib 内部からのみ参照）のどちらかにする
- `RuntimeABISpec` は最終的に「ブリッジ + 言語コア（GC/boxing/coroutine/メタデータ）」のみを宣言する。
  specVersion は縮小のたびに更新する

### ライセンス表記（本家移植部品）

`Sources/CompilerCore/Stdlib/kotlin/` 以下のうち、kotlin-stdlib 本家
（`https://github.com/JetBrains/kotlin` の `libraries/stdlib/src/` 以下）から
コード・構造・定数値を移植したファイルは、Apache License, Version 2.0 に基づく
帰属ヘッダをファイル先頭に付ける。

```kotlin
/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/...>.
 */
```

- 移植元パスとファイル名を可能な限り明記する。
- 本家からの移植でない KSwiftK 独自実装（MIGRATION コメントで Swift Runtime から
  移行したもの等）にはこのヘッダを付けない。
- リポジトリルートに `NOTICE` を置き、本プロジェクトが kotlin-stdlib 由来のコードを
  含むことを記載する。

## 7. コンパイル時間戦略とキャッシュ

方針: **都度コンパイル + 計測から始め、閾値超過で初めてキャッシュを設計する**（早すぎる最適化をしない）。

1. 現状 (~2,300 行) は毎回フロントエンドに乗せる。`PhaseTimer` で
   「bundled stdlib 由来の Lex/Parse/Sema 時間」を分離計測できるようにする（RF-STDLIB-006）
2. 計測ゲート: stdlib 注入によるコンパイル時間の増分が **hello.kt 相当の小入力で +100ms** を超えたら
   キャッシュ着手のトリガーとする（[`docs/refactoring-metrics.md`](refactoring-metrics.md) で正式化済み:
   ベースライン中央値 37.29ms、トリガー = 中央値 ≥ 137.29ms）
3. キャッシュの段階案（トリガー後に選択）:
   - **案 A: pre-parse キャッシュ** — コンパイラビルド時に bundled .kt をトークン列/AST へ
     シリアライズし同梱（`IncrementalCompilationCache` の仕組みを流用）。実装コスト小
   - **案 B: Sema 済みシンボルテーブルの同梱**（klib 的方向）。効果最大だが
     シリアライズ形式の設計・golden への影響が大きい。stdlib が数万行規模になるまで保留
4. ユーザー側の `IncrementalCompilationCache` に対しては、bundled ソースは
   「コンパイラバージョンにのみ依存する固定入力」として扱い、ユーザー入力の変更で再検証しない

> 補足: 並行メモが提案していた別基準（Smoke 相当の入力で wall-clock 15%未満 or 200ms未満）との
> すり合わせは決着済み。実測に基づき上記 +100ms トリガーを採用した（`docs/refactoring-metrics.md`）。

## 8. golden / diff_kotlinc への影響 (RF-STDLIB-007)

- golden（Lexer/Parser/Sema/Diagnostics）は **ユーザー入力ファイルのみ**を対象とし、
  `__bundled_*` 由来のトークン・AST・診断はダンプに含めない（既にパス名で判別可能）
- ただし Sema golden のシンボル ID は bundled ソースの宣言数に影響される。
  §4 の決定的順序（辞書順・ユーザーより先）を不変条件とし、stdlib 変更時は
  `UPDATE_GOLDEN=1` での一括更新を許容する（更新 diff が機械的であることを PR でレビュー）
- stdlib ソース自身に diagnostics が出る状態はコンパイラのバグとして扱う
  （warning 含めゼロを CI で enforcing にする）
- `diff_kotlinc.sh`: 移行した各 API に対応する diff ケースを `Scripts/diff_cases/` に**必ず追加**する。
  kotlinc と意図的に挙動を変えない限り `// SKIP-DIFF` は使わない

実装ステータス（2026-07-06）:

- `LoadSourcesPhase` は bundled / residual stdlib sources を `__bundled_*` path の辞書順に登録し、
  `Tests/CompilerCoreTests/Driver/BundledStdlibOrderingTests.swift` が「bundled がユーザー入力より先」
  と「bundled 同士が辞書順」を固定している
- Sema golden は `Sources/GoldenHarnessSupport/GoldenHarnessDump.swift` で bundled declSite symbols を
  除外し、`rg '__bundled_' Tests/CompilerCoreTests/GoldenCases` が 0 件になる状態を維持する
- Diagnostics golden / CLI diagnostics は `DiagnosticEngine.render` / `renderJSON` が source location、
  severity、code、message で render 時ソートする
- `Scripts/diff_kotlinc.sh` は `find | sort` の case discovery、interleaved sharding、parallel worker logs の
  input-order replay で report / console output の順序を安定化している

## 9. 合成スタブ 3 分類棚卸し (RF-STUB-001)

分類基準:

| 分類 | 基準 | 出口 |
|---|---|---|
| (a) 削除 | JS/Wasm/JVM 固有など KSwiftK のターゲット外、または架空 API（fiction audit 参照） | CLEANUP-STUB-001〜084 で登録呼び出しごと削除 |
| (b) Kotlin 移行 | 純ロジックで Kotlin + ブリッジで書ける | M1–M17 の縦切りで .kt 化しスタブ削除 |
| (c) 組込残留 | `Any`/プリミティブ/`Nothing`/演算子・言語コア、GC/coroutine 機構と不可分 | RF-STUB-003 の宣言テーブル化で残留 |

全 `HeaderHelpers+Synthetic*` ファイルの (a)/(b)/(c) 分類表（2026-07-02 時点、`DUMP_SURFACE=1` の
fiction audit ダンプを起点に棚卸し）:

| File | Lines | Bucket | Owner / next action |
|---|---:|:---:|---|
| `HeaderHelpers+SyntheticArrayStubs.swift` | 2043 | (c) | Array and primitive-array compiler surface; split source-backed factories/HOF later. |
| `HeaderHelpers+SyntheticAtomicStubs.swift` | 2512 | (b) | `AtomicMigration.kt` owner; split Java atomic interop cleanup pockets first. |
| `HeaderHelpers+SyntheticBase64Stubs.swift` | 830 | (b) | MIGRATION-ENC owner; Kotlin source exists but public stubs still dispatch directly. |
| `HeaderHelpers+SyntheticBigIntegerStubs.swift` | 620 | (a) | `java.math.BigInteger` compatibility; target-out cleanup candidate. |
| `HeaderHelpers+SyntheticBuilderDSLStubs.swift` | 414 | (b) | M3 collection builder source migration. |
| `HeaderHelpers+SyntheticCInteropStubs.swift` | 3065 | (c) | Kotlin/Native interop compiler/runtime surface; table-driven residual candidate. |
| `HeaderHelpers+SyntheticCharStubs.swift` | 889 | (c) | Primitive `Char` shell plus helpers; RF-STUB-003 declarative residual registration started here. |
| `HeaderHelpers+SyntheticClockStubs.swift` | 451 | (b) | M8 time source migration. |
| `HeaderHelpers+SyntheticCloseableStubs.swift` | 277 | (b) | `Closeable`/`use` common surface; move to Kotlin source before deleting. |
| `HeaderHelpers+SyntheticCoercionStubs.swift` | 1349 | (b) | M6 range/coercion source migration; many overloads already source-backed. |
| `HeaderHelpers+SyntheticCollectionTypeAliases.swift` | 272 | (b) | M3 collection typealias/source migration. |
| `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift` | 631 | (b) | Core collection/comparable shells; source migration owner, with residual type hooks. |
| `HeaderHelpers+SyntheticComparableHelpers.swift` | 168 | (c) | Helper-only file for residual comparable registration. |
| `HeaderHelpers+SyntheticComparatorStubs.swift` | 1446 | (b) | M5 comparisons/comparator source migration. |
| `HeaderHelpers+SyntheticComparisonStubs.swift` | 1083 | (b) | M5 `maxOf`/`minOf` and comparison helpers. |
| `HeaderHelpers+SyntheticConcurrencyStubs.swift` | 186 | (a) | `java.lang.Thread` / JVM-style `kotlin.concurrent.thread`; cleanup candidate. |
| `HeaderHelpers+SyntheticCoroutineRegistry.swift` | 3552 | (c) | RF-STUB-005 consolidated coroutine package, ABI, and helper registry. |
| `HeaderHelpers+SyntheticDeepRecursiveStubs.swift` | 324 | (b) | Public stdlib surface; source migration before removal. |
| `HeaderHelpers+SyntheticDurationStubs.swift` | 1390 | (b) | M8 duration source migration; bridge-only `__kk_*` declarations may remain private. |
| `HeaderHelpers+SyntheticDynamicStubs.swift` | 101 | (a) | Kotlin/JS `dynamic`; cleanup candidate. |
| `HeaderHelpers+SyntheticEnumStubs.swift` | 474 | (c) | Enum compiler surface. |
| `HeaderHelpers+SyntheticExceptionStubs.swift` | 787 | (c) | Core exception shells required by diagnostics/lowering; RF-STUB-003 declarative residual registration started here. |
| `HeaderHelpers+SyntheticExperimentalBitwiseStubs.swift` | 99 | (b) | Experimental bitwise stdlib helpers; source migration owner. |
| `HeaderHelpers+SyntheticExperimentalMarkerStubs.swift` | 367 | (c) | Common opt-in markers stay; split JS/Wasm markers into (a) cleanup first. |
| `HeaderHelpers+SyntheticExperimentalTimeStubs.swift` | 828 | (b) | M8 experimental time source migration. |
| `HeaderHelpers+SyntheticFileIOStubs.swift` | 2532 | (a) | `java.io.File` / JVM I/O compatibility dominates; split private source bridges if retained. |
| `HeaderHelpers+SyntheticFileTreeWalkStubs.swift` | 291 | (a) | JVM file-walk compatibility; cleanup candidate. |
| `HeaderHelpers+SyntheticFileWalkDirectionStubs.swift` | 113 | (a) | JVM file-walk support enum; cleanup with file-walk surface. |
| `HeaderHelpers+SyntheticFilesUtilityStubs.swift` | 520 | (a) | `java.nio.file` / files utility surface; target-out cleanup. |
| `HeaderHelpers+SyntheticFunctionTypeStubs.swift` | 523 | (c) | Function interfaces are compiler-known. |
| `HeaderHelpers+SyntheticGroupingStubs.swift` | 373 | (b) | M3 grouping/HOF source migration. |
| `HeaderHelpers+SyntheticHexFormatStubs.swift` | 589 | (b) | MIGRATION-ENC owner; source exists but not fully wired. |
| `HeaderHelpers+SyntheticInstantStubs.swift` | 441 | (b) | M8 time source migration. |
| `HeaderHelpers+SyntheticIterableRegistry.swift` | 2741 | (b) | RF-STUB-005 consolidated Iterable/Collection shells and member registrations. |
| `HeaderHelpers+SyntheticIteratorStubs.swift` | 272 | (c) | Iterator and primitive iterator compiler surface; RF-STUB-003 declarative residual registration started here. |
| `HeaderHelpers+SyntheticJsAnyStubs.swift` | 25 | (a) | Kotlin/JS surface; cleanup candidate. |
| `HeaderHelpers+SyntheticJsArrayExternalClassStubs.swift` | 80 | (a) | Kotlin/JS surface; cleanup candidate. |
| `HeaderHelpers+SyntheticJsArrayStubs.swift` | 71 | (a) | Kotlin/JS surface; cleanup candidate. |
| `HeaderHelpers+SyntheticJsFunctionStubs.swift` | 77 | (a) | Kotlin/JS `js(...)`; cleanup candidate. |
| `HeaderHelpers+SyntheticJsNumberStubs.swift` | 117 | (a) | Kotlin/JS number bridge; cleanup candidate. |
| `HeaderHelpers+SyntheticJsStringInteropStubs.swift` | 183 | (a) | Kotlin/JS string interop; cleanup candidate. |
| `HeaderHelpers+SyntheticKotlinAnnotationStubs.swift` | 790 | (c) | Core annotation and opt-in metadata surface. |
| `HeaderHelpers+SyntheticKotlinIOExceptionStubs.swift` | 133 | (b) | `kotlin.io` exception shell; source/runtime migration owner. |
| `HeaderHelpers+SyntheticKotlinVersionStubs.swift` | 372 | (b) | Public stdlib value surface; source migration owner. |
| `HeaderHelpers+SyntheticListAggregateMembers.swift` | 1288 | (b) | M3 list aggregate/source migration. |
| `HeaderHelpers+SyntheticListConversionMembers.swift` | 434 | (b) | M3 list conversion/source migration. |
| `HeaderHelpers+SyntheticListIndexedAndArrayDequeStubs.swift` | 690 | (b) | M3 `IndexedValue` / `ArrayDeque` source migration. |
| `HeaderHelpers+SyntheticListStubs.swift` | 1967 | (b) | M3 list shell and member migration. |
| `HeaderHelpers+SyntheticListTransformMembers.swift` | 797 | (b) | M3 list transform/source migration. |
| `HeaderHelpers+SyntheticLocaleConstructorStubs.swift` | 401 | (a) | `java.util.Locale`/locale interop; cleanup candidate unless retained behind private bridge. |
| `HeaderHelpers+SyntheticMapStubs.swift` | 1255 | (b) | M3 map shell and HOF source migration. |
| `HeaderHelpers+SyntheticMathStubs.swift` | 953 | (b) | Math stdlib source migration, with numeric primitive hooks. |
| `HeaderHelpers+SyntheticMetadataAnnotations.swift` | 15 | (c) | Metadata helper surface. |
| `HeaderHelpers+SyntheticMetaprogAnnotationHelpers.swift` | 953 | (c) | Annotation infrastructure; split JVM-only annotations into (a) before table migration. |
| `HeaderHelpers+SyntheticMutableCollectionArrayAddAll.swift` | 109 | (b) | M3 mutable collection helper source migration. |
| `HeaderHelpers+SyntheticMutableCollectionIterableAddAll.swift` | 104 | (b) | M3 mutable collection helper source migration. |
| `HeaderHelpers+SyntheticMutableCollectionSequenceAddAll.swift` | 101 | (b) | M3/M4 mutable collection helper source migration. |
| `HeaderHelpers+SyntheticMutableListStubs.swift` | 1549 | (b) | M3 mutable list shell and member migration. |
| `HeaderHelpers+SyntheticNativeConcurrentCommon.swift` | 736 | (c) | RF-STUB-004 shared NativeConcurrent helper body. |
| `HeaderHelpers+SyntheticNativeConcurrentRegistry.swift` | 2715 | (c) | RF-STUB-004 consolidated NativeConcurrent registration table and entry point. |
| `HeaderHelpers+SyntheticNativeDataStubs.swift` | 821 | (c) | Native data/runtime support; declarative residual candidate. |
| `HeaderHelpers+SyntheticNativeFunctionAnnotationStubs.swift` | 85 | (a) | `kotlin.js.nativeGetter/nativeSetter/nativeInvoke`; cleanup candidate. |
| `HeaderHelpers+SyntheticNativeInteropHelpers.swift` | 1292 | (c) | Kotlin/Native interop helper surface; table-driven residual candidate. |
| `HeaderHelpers+SyntheticNativeInteropStubs.swift` | 386 | (c) | Kotlin/Native interop annotations/types. |
| `HeaderHelpers+SyntheticNativeRefRuntimeStubs.swift` | 759 | (c) | Native ref runtime support; constructor/member/property surface moved to `SyntheticStubSurfaceSpec+NativeRefRuntime.swift` for RF-STUB-003. |
| `HeaderHelpers+SyntheticOnErrorActionStubs.swift` | 120 | (a) | File-tree walk support; cleanup with file-walk surface. |
| `HeaderHelpers+SyntheticPairTripleStubs.swift` | 409 | (b) | Public `Pair`/`Triple` source migration candidate. |
| `HeaderHelpers+SyntheticPathStubs+GenericFunctionRegistration.swift` | 548 | (a) | `java.nio.file`/`kotlin.io.path`; cleanup with path surface. |
| `HeaderHelpers+SyntheticPathStubs+SymbolRegistration.swift` | 488 | (a) | `java.nio.file`/`kotlin.io.path`; cleanup with path surface. |
| `HeaderHelpers+SyntheticPathStubs+TypeCreation.swift` | 337 | (a) | `java.nio.file`/`kotlin.io.path`; cleanup with path surface. |
| `HeaderHelpers+SyntheticPathStubs.swift` | 2102 | (a) | `java.nio.file`/`kotlin.io.path`; cleanup candidate. |
| `HeaderHelpers+SyntheticBucketedStubRegistry.swift` | 325 | (a/b/c) | RF-STUB-006 bucketed registry for delegate and former ExtendedStdlib calls. |
| `HeaderHelpers+SyntheticPlatformObjectHelpers.swift` | 216 | (a) | Java class/platform object helpers; cleanup unless needed by residual annotations. |
| `HeaderHelpers+SyntheticPlatformTimeConversionStubs.swift` | 261 | (a) | JVM/JS platform time conversion; cleanup candidate. |
| `HeaderHelpers+SyntheticPreconditionStubs.swift` | 205 | (b) | `check`/`require`/`error` source migration. |
| `HeaderHelpers+SyntheticPropertyDelegateStubs.swift` | 2564 | (c) | Delegation and reflection scaffolding; declarative residual candidate. |
| `HeaderHelpers+SyntheticRandomStubs.swift` | 1147 | (b) | M7 random source migration; split Java random interop pockets into (a). |
| `HeaderHelpers+SyntheticRangeInterfaceStubs.swift` | 382 | (b) | M6 range interfaces/source migration. |
| `HeaderHelpers+SyntheticRangeProgressionStubs.swift` | 1116 | (b) | M6 range/progression source migration. |
| `HeaderHelpers+SyntheticRangeUntilStubs.swift` | 142 | (b) | M6 `..<`/`rangeUntil` source migration. |
| `HeaderHelpers+SyntheticReadWriteLockStubs.swift` | 216 | (a) | JVM-style lock compatibility; cleanup or move behind explicit platform bridge. |
| `HeaderHelpers+SyntheticRegexStubs.swift` | 974 | (b) | Regex public stdlib source migration candidate. |
| `HeaderHelpers+SyntheticResultStubs.swift` | 584 | (b) | ~~M13 `Result` source migration~~ **完了・ファイル削除済み**（KSP-304, PR #4566, 2026-07-08）。 |
| `HeaderHelpers+SyntheticScopeFunctionStubs.swift` | 874 | (b) | Scope functions and `takeIf`/`takeUnless` source migration. |
| `HeaderHelpers+SyntheticSequenceRegistrationHelpers.swift` | 1463 | (b) | M4 sequence registration helper surface. |
| `HeaderHelpers+SyntheticSequenceTerminalStubs.swift` | 3452 | (b) | M4 sequence terminal/HOF source migration. |
| `HeaderHelpers+SyntheticSerializationStubs.swift` | 850 | (a) | `kotlinx.serialization` compatibility; target-out cleanup unless retained as explicit library support. |
| `HeaderHelpers+SyntheticSetStubs.swift` | 1068 | (b) | M3 set shell and HOF source migration. |
| `HeaderHelpers+SyntheticStdlibLoopStubs.swift` | 88 | (b) | `repeat` source migration. |
| `HeaderHelpers+SyntheticStringBuilderStubs.swift` | 629 | (b) | M2 StringBuilder source migration; source exists. |
| `HeaderHelpers+SyntheticStringRegistrationHelpers.swift` | 475 | (b) | M1 string helper registration. |
| `HeaderHelpers+SyntheticStringStubs.swift` | 4180 | (b) | M1 string source migration; bridge-only `__kk_*` declarations may remain private. |
| `HeaderHelpers+SyntheticStringTypeHelpers.swift` | 299 | (c) | String type scaffolding and helper utilities. |
| `HeaderHelpers+SyntheticTODOAndIOStubs.swift` | 1347 | (b) | Mixed TODO, IO, system, duration, collection factories; split JVM/system pockets before broad M migration. |
| `HeaderHelpers+SyntheticTestStubs.swift` | 178 | (a) | `kotlin.test` test-only compatibility; cleanup outside production stdlib. |
| `HeaderHelpers+SyntheticThreadLocalStubs.swift` | 215 | (c) | Native/thread-local annotation support. |
| `HeaderHelpers+SyntheticTypedRangeStubs.swift` | 1090 | (b) | M6 typed range source migration. |
| `HeaderHelpers+SyntheticURIStubs.swift` | 178 | (a) | `java.net.URI`; cleanup candidate. |
| `HeaderHelpers+SyntheticURLStubs.swift` | 332 | (a) | `java.net.URL`; cleanup candidate. |
| `HeaderHelpers+SyntheticUnsignedRangeStubs.swift` | 561 | (b) | M6 unsigned range source migration. |
| `HeaderHelpers+SyntheticUuidStubs.swift` | 888 | (b) | M12 UUID source migration; source exists. |
| `HeaderHelpers+SyntheticW3CDomStubs.swift` | 78 | (a) | Kotlin/JS DOM surface; cleanup candidate. |

Mixed files are assigned to the bucket that owns most of the file today. The
notes column calls out sub-blocks that should be split before the final delete or
table migration.

### RF-STUB-002 reference cleanup recipe

`CLEANUP-STUB-033/034` already removed the old PlatformAndJS phase file. RF-STUB-006
now routes the central delegate sequence and the remaining former ExtendedStdlib calls
through `HeaderHelpers+SyntheticBucketedStubRegistry.swift`, where entries are tagged
as (a)/(b)/(c) while preserving historical registration order. The remaining (a) work
should follow the same shape:

1. Remove the registration call from `registerSyntheticDelegateStubs` or the
   relevant phase batch.
2. Delete the stub file, or split the file first if only some declarations are
   target-out.
3. Delete matching `RuntimeABISpec` entries and runtime `@_cdecl` implementations
   that are no longer emitted.
4. Delete Swift tests and `.golden` expectations that only prove the removed
   target-out surface.
5. Run focused Sema/runtime tests for the touched surface, then run golden
   regeneration only for affected cases.
6. Update `docs/stdlib-fiction-audit.md` with the new synthetic symbol count
   when a phase-sized cleanup lands.

### Follow-up order

1. Finish small (a) deletions that still have direct central calls:
   `SyntheticJsAnyStubs`, `SyntheticJsFunctionStubs`, `SyntheticJsNumberStubs`.
2. Split mixed files before touching their residual parts:
   `SyntheticExperimentalMarkerStubs`, `SyntheticMetaprogAnnotationHelpers`,
   `SyntheticRandomStubs`, `SyntheticTODOAndIOStubs`, `SyntheticAtomicStubs`.
3. After RF-STDLIB-003, migrate one narrow (b) slice end-to-end and use it as the
   template for the remaining M1-M17 rows.
4. Continue RF-STUB-003 residual table migration only on files classified (c); do not table-drive code
   that is already scheduled for deletion or Kotlin source migration. `SyntheticNativeRefRuntimeSurfaceSpec`
   is the current reference pattern for residual constructor/member/property tables.

### KSP-498: `kotlin.coroutines` / Flow / Channel の (c)/(b) 分類確定

対象は `HeaderHelpers+SyntheticCoroutineRegistry.swift`（上表で (c) 一括計上済み）が橋渡しする Runtime 実装。
1ファイルに (b) 候補と (c) 確定が混在するため、上表のファイル単位より一段細かいシンボル系統単位で分類する。
**本節はコード変更を含まない**（棚卸しと分類の記録のみ）。

#### 対象 Runtime ファイル（2026-07-08 時点で再計測）

| File | Lines | `kk_*` 関数数 | 主な内容 |
|---|---:|---:|---|
| `RuntimeCoroutine.swift` | 3159 | 65 | suspend/continuation、builder (`kxmini_*`)、Job、`coroutineScope`/`supervisorScope` の内部プリミティブ、timing、context の一部 |
| `RuntimeCoroutineContext.swift` | 726 | 18 | `CoroutineContext`、`Dispatchers`、`ExceptionHandler`、`ContinuationInterceptor` |
| `RuntimeCoroutineChannel.swift` | 656 | 10 | `Channel` 全操作 |
| `RuntimeCoroutineFlow.swift` | 1971 | 33 | `Flow`/`SharedFlow`/`StateFlow` |
| `RuntimeAtomic.swift` | 1550 | 91 | `AtomicInt`/`AtomicLong`/`AtomicBoolean`/`AtomicReference`（配列版含む） |
| `RuntimeSync.swift` | 489 | 16 | `Mutex`/`Semaphore`/`ReadWriteLock` |
| `RuntimeGC.swift`（該当関数のみ） | 15（うち対象2） | 2 | coroutine root の GC 登録・解除 |

6ファイル計 233 関数 + `RuntimeGC.swift` の該当2関数でファイル数は 6+1 = **7**（TODO.md の「7 ファイル」に一致）。
関数総数「279」は 2026-07-01 棚卸し時点の値で、その後の dead code 削除（例: `kk_java_atomic_int_asKotlinAtomic`
削除（CLEANUP-STUB-024, #4409）、test-only dead code 削除 #4478）により減少している。以降の数値は本節時点の実測を正とする。

#### スタブ（Sema 宣言）側の現状

TODO.md の「23 スタブファイル」も同じく 2026-07-01 時点の値。2026-07-06 の RF-STUB-005（#4544, commit `8e05a7cd6`）で
`HeaderHelpers+SyntheticCoroutineHelpers.swift`・`HeaderHelpers+SyntheticCoroutinesStubs.swift` 等の分割ファイルが
`HeaderHelpers+SyntheticCoroutineRegistry.swift`（3552 行、上表で (c) 計上済み）へ統合された。`Mutex`/`Semaphore`/
`Channel`/`Flow`/`SharedFlow`/`StateFlow` の宣言は現在すべてこの1ファイルに集約されている。`Atomic` 系宣言のみ
従来どおり `HeaderHelpers+SyntheticAtomicStubs.swift`（2541 行、上表で (b) 計上済み）に分離されている。
**KSP-499 以降が触るスタブファイルはこの2つのみ**（棚卸し時点の分割ファイル群は現存しない）。

#### (c) 残留（`__kk_` 降格のみ）— 114 関数

| 系統 | 代表シンボル | 数 | ファイル |
|---|---|---:|---|
| suspend 機構・continuation | `kk_suspend_coroutine`, `kk_coroutine_suspended`, `kk_coroutine_continuation_{context,factory,new,resume,resume_with,resume_with_exception}`, `kk_coroutine_state_{enter,exit,get_completion,get_spill,get_thrown_exception,set_completion,set_label,set_spill}`, `kk_create_coroutine_unintercepted`, `kk_start_coroutine_unintercepted_or_return`, `kk_continuation_intercepted`, `kk_continuation_interceptor_intercept_continuation`, `kk_exception_handler_{new,create,invoke}`, `kk_is_cancellation_exception` | 24 | Coroutine / Context |
| builder・Job・構造化並行の内部プリミティブ | `kk_kxmini_{launch,launch_with_cont,launch_with_dispatcher,launch_with_dispatcher_and_cont,launch_with_exception_handler,async,async_await,async_with_cont,run_blocking,run_blocking_with_cont,produce_with_cont}`, `kk_produce`, `kk_job_{join,await_completion,cancel,cancel_with_cause,complete,complete_exceptionally,is_active,is_cancelled,is_completed,is_failed}`, `kk_coroutine_scope_*`(8), `kk_supervisor_scope_*`(3), `kk_coroutine_launcher_arg_{get,set}` | 35 | Coroutine |
| Channel | `kk_channel_{send,receive,create,close,is_closed_for_send,is_closed_for_receive,is_closed_token,iterator,iterator_hasNext,iterator_next}` | 10 | Channel（全関数） |
| timing | `kk_kxmini_delay`, `kk_with_timeout`, `kk_with_timeout_or_null`, `kk_coroutine_yield` | 4 | Coroutine |
| 同期プリミティブ | `kk_mutex_*`(7), `kk_lock_withLock`, `kk_semaphore_*`(5), `kk_{read_write_lock,reentrant_read_write_lock}_*`(3) | 16 | Sync（全関数） |
| context | `kk_context_*`(9), `kk_coroutine_name_{create,get}`, `kk_dispatcher_{default,io,main}`, `kk_with_context{,_full}`, `kk_coroutine_{current_context,cancel,cancel_current,check_cancellation}` | 20 | Context / Coroutine |
| Flow ブリッジ（cold Flow の最小核） | `kk_flow_create`, `kk_flow_emit`, `kk_flow_collect` | 3 | Flow |
| （参考・別系統だが同性質）GC root 登録 | `kk_register_coroutine_root`, `kk_unregister_coroutine_root` | 2 | GC |

#### (b) 候補（KSP-499 以降で移行）— 103 関数 + 新規実装分

| 系統 | 代表シンボル | 数 | ファイル | 備考 |
|---|---|---:|---|---|
| Flow terminal（到達可能・要 Lowering 変更） | `kk_flow_{to_list,first,single}` | 3 | Flow | 下記「Flow (b) 移行の前提条件」参照 |
| Flow terminal（未到達・デッドコード） | `kk_flow_{fold,reduce,count}` | 3 | Flow | Sema 宣言・Lowering 書き換えのどちらの対象にもなっておらず、現状呼び出す経路が存在しない |
| Flow 合成（到達可能・要 Lowering 変更） | `kk_flow_{merge,zip,combine,flat_map_concat,flat_map_latest,flat_map_merge}` | 6 | Flow | 下記「Flow (b) 移行の前提条件」参照 |
| Atomic 全般 | `kk_atomic_{int,long,bool,ref}_*`（scalar + 配列 `*At`） | 91 | Atomic | 詳細は下記 |
| `coroutineScope`/`supervisorScope`（公開ラッパー） | ― | 新規 | ― | 内部は (c) の `kk_coroutine_scope_*`/`kk_supervisor_scope_*` へ委譲する薄い Kotlin 関数にする。primitives 自体は (c) のまま |
| Flow per-element | `map`/`filter`/`take`/`debounce` | 0（未実装） | ― | 既存 Swift 実装なし。移行ではなく KSP-499 での新規 Kotlin 実装（`collect`+`emit` 合成）として着手 |

**Flow (b) 移行の前提条件（要 verify、コード確認済み 2026-07-08）**: `Sources/CompilerCore/Lowering/CoroutineLoweringPass+Flow.swift`
の `lowerFlowExpressions` は `map`/`filter`/`take`/`transform`/`single`/`takeWhile`/`dropWhile`/`flatMapConcat`/`flatMapMerge`/
`flatMapLatest`/`combine`/`zip`/`merge`/`buffer`/`conflate`/`flowOn`/`debounce`/`sample`/`delayEach`/`catch`/`retry`/`retryWhen`/
`onErrorReturn`/`onErrorResume`/`toList`/`first` の呼び出しを、**Sema が解決した callee symbol を参照せず**、
「レシーバが flow 由来の式かどうか（`flowExprIDs`/`flowGlobalSymbols` による provenance 追跡）」+「呼び出し名の文字列一致」
だけで `kk_flow_*` へ KIR 構造的に書き換える。したがって、これらの名前を持つ Kotlin 実装を bundled stdlib に追加しても
**Lowering 段階で無条件に上書きされ、呼ばれない**（`FlowLoweringNames` 構造体・その初期化コードに列挙された名前が対象）。
Flow terminal/合成を (b) 化するには、このパスを「対象シンボルが `kk_flow_*` 系の合成スタブ由来と確認できる場合のみ」に
絞るか、対象名を初期化リストから外す変更が**同一 PR で必須**（`docs/stdlib-pipeline.md` の他モジュールで確立している
「.kt を書いて stub/cdecl を消せば移行完了」という Template T はここでは通用しない）。着手前に必ずダミー実装の
差し替えテスト（例: `suspend fun <T> Flow<T>.toList(): List<T> = listOf()` を bundle し、実際の `flowOf(1,2,3).toList()`
の戻り値がダミーの空リストになるかを確認）で再検証すること。

Atomic の内訳:

- **委譲パターン適用済み**: `get`/`set`/`getAndSet`/`incrementAndGet`/`decrementAndGet`/`addAndGet`（`AtomicInt`/`AtomicLong`/
  `AtomicReference`）は `Sources/CompilerCore/Stdlib/kotlin/concurrent/AtomicMigration.kt`（47行）で Kotlin 化済み。
  委譲先の `kk_atomic_{int,long,ref}_{load,store,exchange,incrementAndFetch,decrementAndFetch,addAndFetch}` は実質
  (c) ブリッジ（`__kk_` 未リネームのみが残タスク）
- **未着手**: `compareAndSet`/`compareAndExchange`/`getAndUpdate`/`updateAndGet`（scalar + 配列 `*At`。`AtomicBoolean`
  は上記委譲が未実施のため全操作が対象）。`updateAndGet`/`getAndUpdate` は `while(true)` ループを要するため、
  `AtomicMigration.kt` のコメントの通り「bundled ソースで Nothing 型無限ループの型検査が通る」まで**ブロック**。
  `compareAndSet`/`compareAndExchange` 自体はハードウェア CAS 命令への直接ブリッジなので、移行後も (c) `__kk_`
  残留になると想定される

#### 未分類・KSP-499 着手前に個別判断が必要な項目 — 18 関数

指示された分類に直接対応がない `RuntimeCoroutineFlow.swift` の残り:

- **SharedFlow/StateFlow（hot flow）**: `kk_mutable_shared_flow_{create,emit,try_emit}`, `kk_mutable_state_flow_{create,emit,try_emit}`,
  `kk_shared_flow_{collect,replay_cache}`, `kk_state_flow_value`, `kk_flow_{share_in,state_in,stopped,release,retain}`（計14関数）。
  replay buffer・購読者管理を伴い Channel に近い可能性があり (c) 寄りと推測するが要検証
- **Flow builder**: `kk_flow_{as_flow,empty,of}`（計3関数）。`kk_flow_create` + `kk_flow_emit` の合成で (b) 化できる
  可能性が高い。なお `channelFlow`/`callbackFlow` は Sema 側のみ登録されており Runtime 実装は未確認（Channel 実体を
  持つ可能性が高く (c) 濃厚）
- `kk_flow_emit_with_timestamp`（1関数）: 用途未確認。将来の `debounce`/`sample` 系実装が必要とする可能性があるため
  KSP-499 着手時に再調査

## 10. モジュール移行プレイブック

各 M フェーズ（および RF-STDLIB-004/005 の縦切り）は同一手順で回す。
**完了条件は「.kt 実配線 + 合成スタブ削除 + runtime 関数削除または `__kk_*` 降格」**（RF-STDLIB-008）。

1. 対象 API の diff ケースを `Scripts/diff_cases/` に追加し、現行実装で green を確認する（挙動の固定）
2. `.kt` を書く（配置・命名は §6）。ランタイム依存点は `@KsSymbolName` ブリッジで宣言する
3. `excludedBundledStdlibFiles` からエントリを削除して配線する
4. 優先規則（§5）により Kotlin 版が解決されることを確認し、**同一 PR で**対応する
   合成スタブ・`CallTypeChecker`/`CallLowerer` の特殊処理・runtime `@_cdecl` を削除
   （または `__kk_*` へ降格）する
5. 必須ゲート（CLAUDE.md）: `swift_test.sh` 全体 / Golden / `diff_kotlinc.sh` green、
   `loc_report.sh` で `HeaderHelpers+Synthetic*` 行数と `"kk_` リテラル数の減少を確認する
6. TODO.md の該当タスクを更新する

進捗メトリクス = `loc_report.sh` の (i) `HeaderHelpers+Synthetic*` 合計行数、(ii) `"kk_` リテラル数、
(iii) `interner.resolve == "..."` 数。すべて単調減少がゲート。

## 11. 実装順序

| 順 | タスク | 内容 |
|---|---|---|
| 1 | RF-STDLIB-003 | 優先規則 + 二重定義 warning（§5） |
| 2 | RF-STDLIB-004 | 縦切り第1弾 `StringComparison.kt`（プレイブック §10 のテンプレート化） |
| 3 | RF-STDLIB-006/007 | PhaseTimer 計測（§7）+ golden 決定性の正規化（§8） |
| 4 | `@KsSymbolName` 導入 | ブリッジ注釈 + ABI 突合テスト（§6）。最初にブリッジが必要な縦切りと同時でよい |
| 5 | RF-STDLIB-005 | 縦切り第2弾 `StringSplitJoin.kt`（`kk_string_split*` の `__kk_*` 降格を含む） |
| 6 | RF-STUB-001 | 3分類棚卸し表を §9 に追記 → M1–M17 とCLEANUP-STUB を並列展開 |

## 12. 附録: 並行策定分の統合待ち事項

master 側 (#4483) でも同時期に同テーマの設計メモが独立に書かれていた（`docs/stdlib-pipeline.md` の
add/add コンフリクト）。本文（§1–11、§9 の棚卸し表を除く）と重複する記述は失わないよう本文へ統合済みだが、
以下は本文にない追加提案であり、レビューで採否・統合先を決めること。

> 2026-07-10 更新: 本節の各案は TODO.md でタスク化された — SourceManager origin = KSP-INF-008、
> 専用診断コード = KSP-INF-009、二重定義4象限 = KSP-INF-011、インクリメンタルキャッシュ = KSP-INF-002。

- ~~**コンパイル時間の許容閾値が §7 と異なる**~~: **決着済み**。RF-STDLIB-006 の実測
  （`docs/refactoring-metrics.md` の Bundled Stdlib Injection Cost）に基づき §7 の
  「+100ms トリガー」を正式採用した。
- **SourceManager の origin 概念**: ファイルパスの `__bundled_` prefix 判定だけに依存せず、
  `user` / `bundledStdlib` / `residualStdlib` の 3 値 origin を `SourceManager` に持たせる具体案
  （既存の prefix 判定は互換期間として残す）。golden・diagnostics のソートキーを
  「origin → normalized path → source offset → declaration stable key」の 4 段にする案も含む。
- **専用診断コード**: bundled stdlib の読み込み失敗を、ユーザー入力の `KSWIFTK-SOURCE-0002` とは別に
  `KSWIFTK-SOURCE-0101`（リソースディレクトリ不在）/ `KSWIFTK-SOURCE-0102`（読み込み失敗）として
  切り出す具体案。
- **二重定義の扱いの 4 象限（決着）**: `BundledDeclarationIndex` + `BundledSyntheticStubRegistration.shouldSkipRegistration` で一元化。
  1. **bundled stdlib source vs synthetic stub**: bundled source が存在する `(owner, name, arity)` に対する合成スタブは登録をスキップする（KSP-002 宣言優先規則）。ガード漏れは `KSWIFTK-SEMA-0102` で検出・警告する。
  2. **bundled stdlib source vs residual stdlib source**: 両方とも `SourceOrigin.isBundledStdlib` で収集される `BundledDeclarationIndex` の対象。同 key が衝突した場合は bundled source（`__bundled_*.kt`）を優先し、residual source は宣言面のフォールバックとする。
  3. **user source vs bundled stdlib source**: ユーザー入力が bundled source と同名・同 arity・同 receiver owner の拡張を定義した場合、ユーザー定義を優先する。合成スタブ登録前の `symbols.lookup(fqName:)` と `shouldSkipRegistration` の `receiverOwnerFQName` 解決により実現する。
  4. **user source vs synthetic stub**: ユーザー入力が synthetic stub と同じ member を定義した場合、ユーザー定義を優先する。各 `registerSyntheticXxx` は `symbols.lookup(fqName:)` が `nil` の場合のみ登録する。
  - **runtime-backed 互換ブリッジの例外**: `List`/`Iterable`/`Sequence` 等の一部 HOF・検索・sort・端末変換は、Kotlin 化 source があっても `kk_*` ABI 経由で呼ばれる移行期橋渡しとして合成スタブを残す。これらは `BundledDeclarationIndex.isRuntimeBackedSyntheticRetainedOverlap` にホワイトリスト化し、`warnSyntheticOverlaps` では警告しない。`joinTo`/`joinToString` の transform overload も、arity では default overload と区別できないため function-typed パラメータ検出で false-positive を抑制する。
- **インクリメンタルキャッシュへの影響**: `IncrementalCompilationCache.computeCurrentFingerprints` に
  bundled/residual stdlib の virtual path + content hash を含める案、`IncrementalBuildConfiguration` へ
  stdlib source manifest hash・opt-out フラグを追加する案、stdlib fingerprint 変更時は当面
  full frontend rebuild に倒す方針。

## 13. 移行ガバナンス（2026-07-10 ギャップ監査で制定）

理想像の明確化: **stdlib は限りなく Pure Kotlin、Swift はコンパイラとしての機能提供に集中する**。
Swift に残ってよいのは (1) 言語コアの組込宣言（Any/Nothing/プリミティブ/演算子/関数型 invoke）、
(2) GC・alloc・boxing・coroutine continuation 機構・型メタデータレジストリ、(3) OS/ハードウェア syscall のみ。
「既に Swift ランタイムに実装があるから」「ロジックが複雑だから」は (c) 残留の理由にならない。

1. **完了 = enforcing**: タスクの完了条件は「enforcing テスト or rg チェックが存在して green」のみ。
   ドキュメント同期・部分検証での完了マークは禁止（教訓: KSP-008 の `--no-stdlib` デッドフラグ、
   KSP-103 のアリティのみ突合）。完了メモには検証コマンドと green 実績を必記する。
2. **ブリッジ入場審査と予算**: `__kk_*` を追加する PR は、理由コード
   （syscall / メモリ表現 / GC・continuation / メタデータ / 性能=実測値添付）+ `RuntimeABISpec` 登録 +
   specVersion 更新 + `__kk_*` 総数メトリクスの悪化理由を必須とする。
3. **性能エスケープハッチは実測必須**: ベンチ数値（KSP-INF-007 の基盤）を添付できない限り、
   性能を理由とした Swift 残留・(c) 分類を認めない。
4. **二重 oracle**: 移行タスクは diff_kotlinc ケースに加え、bundled .kt を実行して期待値比較する
   自己完結テスト（KSP-INF-006）を必須にする（テンプレート T 手順7）。
5. **Capability Matrix**: 言語機能ブロッカーは KSP-CAP-* として独立起票し、各移行タスクは必要 CAP を
   「前提」に宣言する。「〜が駄目なら中断」文言は CAP 参照へ置換する（ブロッカー先行の原則）。
6. **(c) 分類の理由コードと再審査**: (c) には理由コード（言語コア / 機構 / syscall / 性能）を付与し、
   RF-GOV-004 の四半期監査に (c) 再審査を統合する。c-soft（解除条件 = CAP ID）を正式ステータスとする。
   2026-07-10 再監査の結論: 旧 (c) 計上の4〜5割が最終的に (b) へ移動し、約2,800行 + cinterop 未配線外殻が
   削除候補（詳細は TODO.md の KSP-W6 / CLEANUP-STUB-096〜103）。
7. **移行完了の3点確認**（テンプレート T 手順6）: ①`excludedBundledStdlibFiles` 非登録
   ②.kt 本体が実ロジック（`= this` 等のフェイク禁止 — 実例: `ranges/RangeCoercion.kt`）
   ③Sema/KIR/Lowering に同名の name-string 特例が残っていない。
   「bundled .kt が存在する = 移行済み」と誤読しないこと。
8. **本家準拠度・逸脱台帳・ライセンス**: .kt は挙動だけでなく構造も本家 kotlin-stdlib 形を目標とする。
   コンパイラ制約による構造逸脱（例: KSP-466 Random の 1 クラス統合 — KSP-CAP-006 が解消条件）は
   本節配下に台帳化し、CAP 解消時に本家形へ戻す。本家からの移植ファイルには Apache 2.0 帰属ヘッダ +
   リポジトリ NOTICE を付ける（KSP-INF-013）。
9. **タスク運用**: 未完了タスクの削除禁止（`[x]` のみ削除可）。本文から参照される ID は必ず解決可能に保つ
   （M1–M17 / CLEANUP-STUB 個別リスト消失の教訓）。作業中に発見した修正可能なバグは、症状を再現する最小ケースと回帰テストを含めて同じPR内で修正する。
   同じPRのスコープや安全な修正方針を超える場合だけ、BUG-NNN として TODO.md に理由付きで追跡する（CLAUDE.md「バグ修正ルール」）。
10. **粒度**: 1 タスク = 1 PR。目安「削除対象 kk_* ≤ 15・単一責務・golden 更新1回」。
    超えると判明したら枝番でなく新番号で分割する。

### 構造逸脱台帳（§13-8）

| ファイル | 逸脱内容 | 本家形 | 解消条件 |
|---|---|---|---|
| `random/Random.kt` | `Random` 1クラス統合 + セカンダリコンストラクタ | `abstract class Random` + `internal class XorWowRandom` + トップレベル `fun Random(seed)` | KSP-CAP-006（クラスと同名トップレベル関数の共存、解消済み）— 本家形への移行自体は PRNG のビット精度検証を伴う別タスクで実施 |
