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
3. `--no-stdlib` で `CompilerOptions.includeStdlib` を false にし、注入全体を opt-out できる（コンパイラ自身のデバッグ用）
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
| `HeaderHelpers+SyntheticNativeRefRuntimeStubs.swift` | 1135 | (c) | Native ref runtime support; declarative residual candidate. |
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
| `HeaderHelpers+SyntheticResultStubs.swift` | 584 | (b) | M13 `Result` source migration; source exists. |
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
   that is already scheduled for deletion or Kotlin source migration.

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
- **二重定義の扱いの 4 象限**: 本文 §5 は「Kotlin ソース vs 合成スタブ」の 1 象限のみを扱うが、
  並行メモは (1) stdlib source vs synthetic stub、(2) bundled stdlib source vs residual stdlib source、
  (3) user source vs bundled stdlib source、(4) user source vs synthetic stub の 4 組み合わせを
  個別にハンドリング方針化していた。
- **インクリメンタルキャッシュへの影響**: `IncrementalCompilationCache.computeCurrentFingerprints` に
  bundled/residual stdlib の virtual path + content hash を含める案、`IncrementalBuildConfiguration` へ
  stdlib source manifest hash・opt-out フラグを追加する案、stdlib fingerprint 変更時は当面
  full frontend rebuild に倒す方針。
