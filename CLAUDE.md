# CLAUDE.md

AI 向けクイックリファレンス。詳細なアーキテクチャ・ナビゲーション情報は [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) を参照。

## プロジェクト概要

KSwiftK は Swift で書かれた Kotlin コンパイラ。Kotlin 2.3.10 stable をターゲットとし、LLVM 経由で macOS ネイティブ実行ファイルを生成する。実行バイナリは `kswiftc`（LSP サーバ `kswift-lsp` も生成）。

## ビルド & テストコマンド

**動作確認は変更に関係する最低限のスコープで良い。** 既定は `swift build` ＋ 変更箇所を直接カバーするテストだけを `--filter` で回す（→ [動作確認の最小スコープ](#動作確認の最小スコープ)）。

```bash
swift build                              # デバッグビルド
swift build -c release                   # リリースビルド
bash Scripts/swift_test.sh                               # 全テスト（並列）
bash Scripts/swift_test.sh --skip-build                  # ビルド済み成果物を再利用してテストのみ（古いバイナリで偽陽性の罠 → 下記「動作確認の最小スコープ」）
bash Scripts/swift_test.sh --filter SmokeTests           # スモークテスト
bash Scripts/swift_test.sh --filter Golden               # ゴールデン全部（Swift Testing: Lexer / Parser / Sema / Diagnostics）。`Golden` はシンボル名の部分一致
bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden  # Sema ゴールデンのみ（`Golden.Sema` は @Suite 表示名のため --filter に効かない。型名で指定する）
bash Scripts/swift_test.sh --filter CompilerCoreTests.LoweringPassRegressionTests  # 単一 XCTest クラス（フロントエンド）
bash Scripts/swift_test.sh --filter CompilerBackendTests                         # バックエンドテスト（LLVM 必要）
.build/debug/kswiftc path/to/file.kt -o out  # コンパイラを直接実行
```

- 並列実行だと個別 XCTest の "Executed N tests" サマリが出ず 0 tests に見えることがある。実行確認には `SWIFT_TEST_PARALLEL=0` を付ける。
- ワーカー数などの環境変数、Runtime ABI リンク検証（`validate_runtime_abi_links.sh`）、TODO ID 重複検出（`check_todo_ids.sh`）等の補助スクリプトは [`Scripts/README.md`](Scripts/README.md) を参照。

### 動作確認の最小スコープ

ローカルの動作確認は**変更に関係する範囲だけ**で良い。全テスト・全ゴールデン・全 diff ケースの総ざらいを既定の締め作業にしない（全体は CI が回す）。

- 既定: `swift build`（型チェック）＋ 変更箇所を直接カバーするテストのみ `--filter` で指定
- Golden: 変更が golden 出力に影響する場合のみ該当スイートを型名フィルタで回す（四スイート一括の `--filter Golden` は影響範囲が広いときだけ）
- kotlinc 差分: ディレクトリ全体ではなく関係するケース単体（`bash Scripts/diff_kotlinc.sh Scripts/diff_cases/foo.kt`）
- 全体を回すのは、明示的に求められたとき、または CI が落ちた範囲を再現するときに限る
- 時短目的の `--skip-build` 単独使用は避ける（古いテストバイナリで偽陽性が出る）。`swift build` と `swift test --skip-build` の同時実行も禁止
- 回していない範囲は報告に明記する（「◯◯だけ確認、全体は未実行」）。縮小したスコープを green と誤報告しない

### ゴールデンテスト更新

CI（Full Swift Tests）と Swift の言語モードを揃えるなら `-Xswiftc -swift-version -Xswiftc 6` を付ける。

```bash
# 全ゴールデン（Lexer / Parser / Sema / Diagnostics）を一括更新
UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden -Xswiftc -swift-version -Xswiftc 6

# Sema のみ更新する例
UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden -Xswiftc -swift-version -Xswiftc 6

git diff -- Tests/CompilerCoreTests/GoldenCases
```

所要時間を計測したいときは `time swift test --filter CompilerCoreTests.GoldenLexerGoldenTests/matchesGolden` のように型名フィルタで単一スイートを回す（四スイートまとめてなら `--filter Golden`）。

### kotlinc 回帰差分

```bash
bash Scripts/diff_kotlinc.sh Scripts/diff_cases/hello.kt  # 単一ケース
bash Scripts/diff_kotlinc.sh Scripts/diff_cases            # 全ケース
```

CI で diff が落ちたとき: GitHub 上はジョブ **Summary** と **Artifacts**（TSV・失敗ケースディレクトリ）を優先。`gh run view RUN_ID --log-failed` だけだと、kotlinc diff ステップは `continue-on-error` のため **本体ログが含まれない**ことがある。全文ログでは `FAIL ` を grep。

### リファクタ PR のゲート

RF 系リファクタ PR でも、ローカルの動作確認は上記の最小スコープで良い（全体は CI に任せる）。全体を回す必要があるとき（明示的な依頼 / CI 失敗の再現）のコマンドは以下。

```bash
bash Scripts/swift_test.sh
bash Scripts/swift_test.sh --filter Golden
bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

`Scripts/loc_report.sh` が存在する HEAD では、変更前後の TSV を比較し、ディレクトリ別行数、`HeaderHelpers+Synthetic*` 合計行数、KIR/Lowering TODO/FIXME 数、`"kk_` リテラル数、`interner.resolve == "..."` 数、Runtime の `kk_cdecl_count` / `__kk_cdecl_count` の悪化がないことは（動作確認とは別のチェックとして）引き続き確認する（ベースラインは [`docs/refactoring-metrics.md`](docs/refactoring-metrics.md)）。`kk_` 減 + `__kk_` 増の降格ペアは理由コード付きなら許容するが、`__kk_cdecl_count` の純増は§13-2の理由コードと影響範囲をPR本文に明記する。その他の意図的な悪化も、PR 本文に理由・影響範囲・フォローアップ TODO を明記する。

## 長時間ゲートの委譲と自己検証

このリポジトリのゲートは人間の待ち時間より長いので、完了を待ってブロックしない。

- **長時間ゲートはサブエージェントに出す。** `bash Scripts/diff_kotlinc.sh Scripts/diff_cases`（約 1425 ケース、30 分超、PASS/FAIL はケース単位で出るがサマリは最後）や `bash Scripts/swift_test.sh` の全テストは、サブエージェントに渡してその間に別の作業を進める。脱線や文脈不足が見えたら介入する。
- **ただし同じ worktree で `swift build` / `swift test` を重ねない。** 同一 worktree での `swift build` と `swift test --skip-build` の同時実行は 0 CPU で停止し、重量 `swift test` を 2 本同時に起動すると `.outputUnavailable` の偽フレークが出る実績がある。並行させるなら別 worktree か、ビルドを伴わない作業にする。
- **仕様準拠の判定は新しい文脈のサブエージェントに任せる。** RF 系ゲートやゴールデン更新が妥当かは、自己批評よりも、変更の意図を知らないサブエージェントに「[`docs/spec.md`](docs/spec.md) / ゴールデン差分と実装が一致しているか」を検証させた方が精度が高い。差分が大きい更新では、まとめて最後に見るのではなく途中で一度挟む。

## バグ修正ルール

作業中に発見したコンパイラ / ランタイムのバグは、原則として**発見したPR内で修正する**。修正には、症状を再現する最小の Kotlin コード（または `Scripts/diff_cases/` のケース）と、その挙動を固定する回帰テストを同じPRに含める。spawn_task などセッション外への報告だけで、修正可能なバグを先送りしてはならない。


## アーキテクチャ概要

```
LoadSources → Lex → Parse → BuildAST → SemaPasses → BuildKIR → Lowering → Codegen → Link
```

モジュール構成:

- `CompilerCore` — フロントエンド（Lex〜Lowering）、LLVM 非依存
- `CompilerBackend` — Codegen + Link。LLVM は `LLVMCAPIBindings+Loading.swift` で `libLLVM` を dlopen する動的ロード方式（システムターゲットなし）
- `KSwiftKCLI` → `kswiftc` / `LSPServer` + `KSwiftLSPCLI` → `kswift-lsp`
- `Runtime` — GC・coroutine・boxing / `RuntimeABI` — ABI 契約の共有境界
- `GoldenHarnessSupport` / `GoldenHarnessWorker` — ゴールデンテストハーネス
- `Stdlib/kotlin/` — Kotlin ソース化された stdlib（[`docs/stdlib-pipeline.md`](docs/stdlib-pipeline.md)）

詳細なディレクトリマップ・フェーズ仕様・タスク別ナビゲーションは → [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

## コーディング規約

- Swift 6.2（`swift-tools-version: 6.2` / Swift language mode 6）, macOS 12+, 4スペースインデント
- 型/enum/プロトコル: `UpperCamelCase`、関数/変数: `lowerCamelCase`
- フォーマッタ未設定 — 既存ファイルのスタイルに従う
- コミットメッセージ: 短く命令形（例: "Add ...", "Fix ..."）
- 診断コード: `KSWIFTK-{PHASE}-{NUMBER}` 形式（例: `KSWIFTK-SEMA-0001`）
- 分割ファイルは責務ベースで命名（`+Part2` のような番号付き名は禁止）

## 主要ドキュメント

| ファイル | 内容 |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | ディレクトリマップ・データフロー・タスク別ナビゲーション |
| [`docs/spec.md`](docs/spec.md) | フェーズ別実装仕様（Swift 型・API レベル） |
| [`docs/stdlib-pipeline.md`](docs/stdlib-pipeline.md) | Stdlib の Kotlin ソース化: 3層モデル・優先規則・ブリッジ規約・移行プレイブック・移行ガバナンス（§13: 完了=enforcing / ブリッジ入場審査 / Capability Matrix / 粒度ルール） |
| [`docs/debugging.md`](docs/debugging.md) | DWARF / lldb デバッグガイド |
| [`docs/runtime-abi-external-link-validation-gaps.md`](docs/runtime-abi-external-link-validation-gaps.md) | CompilerCore emit `kk_*` 名と `RuntimeABISpec` 照合の検証ギャップ |
| [`docs/refactoring-metrics.md`](docs/refactoring-metrics.md) | LoC / jscpd / stdlib 注入コストのベースライン（リファクタゲートの比較基準） |
| [`docs/diff-skip-inventory.md`](docs/diff-skip-inventory.md) | `SKIP-DIFF` ケースの棚卸しと解除手順（DEBT-DIFF-001〜006） |
| [`Scripts/README.md`](Scripts/README.md) | swift_test.sh の環境変数・補助スクリプト一覧 |
| [`AGENTS.md`](AGENTS.md) | Linux（Cursor Cloud）環境のセットアップ・環境変数 |
| [`TODO.md`](TODO.md) | 未完了タスク一覧 |
