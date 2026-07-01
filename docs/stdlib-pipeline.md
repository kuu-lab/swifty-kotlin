# Stdlib ソースパイプライン設計 (RF-STDLIB-001)

Kotlin ソースで stdlib を実装するための設計メモ。TODO.md の Phase RF2（Stdlib ソースパイプライン基盤）
および M1–M17（モジュール別移行）の共通指針とする。

関連: [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) / [`docs/stdlib-fiction-audit.md`](stdlib-fiction-audit.md) /
[`docs/runtime-abi-external-link-validation-gaps.md`](runtime-abi-external-link-validation-gaps.md)

## 1. 目的とゴール

**ゴール**: stdlib の純ロジック（イテレーション・変換・比較・整形等）を Kotlin ソースとして実装し、
コンパイラ（Swift）側は「言語コア + ランタイムブリッジ」だけを持つ状態にする。

- `HeaderHelpers+Synthetic*`（約130ファイル / 約8.3万行）を、(a) 削除・(b) Kotlin 移行・(c) 真の組込残留の
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
| 合成スタブ (Swift) | `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+Synthetic*.swift` | ~130 ファイル / ~8.3万行 | 主力。Sema 時に宣言登録し `kk_*` へ直結 |
| バンドル Kotlin ソース | `Sources/CompilerCore/Stdlib/kotlin/**/*.kt` | ~20 ファイル / ~2,300 行 | `LoadSourcesPhase` が `__bundled_*.kt` として注入（RF-STDLIB-002 済） |
| インライン Kotlin 文字列 | `Sources/CompilerCore/Driver/BundledKotlinStdlib.swift` | ~550 行 | residual。§6 で廃止対象 |

補足:

- `LoadSourcesPhase.excludedBundledStdlibFiles`（18 エントリ）が「.kt は存在するが未配線」のファイルを
  除外している。除外リストは**移行の暫定措置**であり、最終状態では空にする
- ルート `Stdlib/kotlin/` に死蔵 .kt が残っている（RF-HYG-003/004 参照）。§6 の単一ツリーへ統合する
- ランタイムは `@_cdecl` 関数 ~1,800 個、署名は `RuntimeABISpec`（specVersion 管理）で宣言

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
3. `-no-default-stdlib-sources` で注入全体を opt-out できる（コンパイラ自身のデバッグ用）
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
   キャッシュ着手のトリガーとする（値は初回計測後に `docs/refactoring-metrics.md` で正式化）
3. キャッシュの段階案（トリガー後に選択）:
   - **案 A: pre-parse キャッシュ** — コンパイラビルド時に bundled .kt をトークン列/AST へ
     シリアライズし同梱（`IncrementalCompilationCache` の仕組みを流用）。実装コスト小
   - **案 B: Sema 済みシンボルテーブルの同梱**（klib 的方向）。効果最大だが
     シリアライズ形式の設計・golden への影響が大きい。stdlib が数万行規模になるまで保留
4. ユーザー側の `IncrementalCompilationCache` に対しては、bundled ソースは
   「コンパイラバージョンにのみ依存する固定入力」として扱い、ユーザー入力の変更で再検証しない

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

## 9. 合成スタブ 3 分類棚卸し (RF-STUB-001)

分類基準:

| 分類 | 基準 | 出口 |
|---|---|---|
| (a) 削除 | JS/Wasm/JVM 固有など KSwiftK のターゲット外、または架空 API（fiction audit 参照） | CLEANUP-STUB-001〜084 で登録呼び出しごと削除 |
| (b) Kotlin 移行 | 純ロジックで Kotlin + ブリッジで書ける | M1–M17 の縦切りで .kt 化しスタブ削除 |
| (c) 組込残留 | `Any`/プリミティブ/`Nothing`/演算子・言語コア、GC/coroutine 機構と不可分 | RF-STUB-003 の宣言テーブル化で残留 |

> **TODO**: 全 `HeaderHelpers+Synthetic*` ファイルの (a)/(b)/(c) 分類表をここに追記する
> （RF-STUB-001 の作業項目。fiction audit の `DUMP_SURFACE=1` ダンプを起点に棚卸しする）。

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
