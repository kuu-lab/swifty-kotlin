# CLAUDE.md

AI 向けクイックリファレンス。詳細なアーキテクチャ・ナビゲーション情報は [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) を参照。

## プロジェクト概要

KSwiftK は Swift で書かれた Kotlin コンパイラ。Kotlin 2.3.10 stable をターゲットとし、LLVM 経由で macOS ネイティブ実行ファイルを生成する。実行バイナリは `kswiftc`（LSP サーバ `kswift-lsp` も生成）。

## ビルド & テストコマンド

```bash
swift build                              # デバッグビルド
swift build -c release                   # リリースビルド
bash Scripts/swift_test.sh                               # 全テスト（並列）
bash Scripts/swift_test.sh --skip-build                  # ビルド済み成果物を再利用してテストのみ
bash Scripts/swift_test.sh --filter SmokeTests           # スモークテスト
bash Scripts/swift_test.sh --filter Golden               # ゴールデン全部（Swift Testing: Lexer / Parser / Sema / Diagnostics）。`Golden` はシンボル名の部分一致
bash Scripts/swift_test.sh --filter CompilerCoreTests.GoldenSemaGoldenTests/matchesGolden  # Sema ゴールデンのみ（`Golden.Sema` は @Suite 表示名のため --filter に効かない。型名で指定する）
bash Scripts/swift_test.sh --filter CompilerCoreTests.LoweringPassRegressionTests  # 単一 XCTest クラス（フロントエンド）
bash Scripts/swift_test.sh --filter CompilerBackendTests                         # バックエンドテスト（LLVM 必要）
.build/debug/kswiftc path/to/file.kt -o out  # コンパイラを直接実行
```

- 並列実行だと個別 XCTest の "Executed N tests" サマリが出ず 0 tests に見えることがある。実行確認には `SWIFT_TEST_PARALLEL=0` を付ける。
- ワーカー数などの環境変数、Runtime ABI リンク検証（`validate_runtime_abi_links.sh`）、TODO ID 重複検出（`check_todo_ids.sh`）等の補助スクリプトは [`Scripts/README.md`](Scripts/README.md) を参照。

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

### リファクタ PR 必須ゲート

RF 系リファクタ PR は、原則として以下をすべて green にしてから完了扱いにする。

```bash
bash Scripts/swift_test.sh
bash Scripts/swift_test.sh --filter Golden
bash Scripts/diff_kotlinc.sh Scripts/diff_cases
```

`Scripts/loc_report.sh` が存在する HEAD では、変更前後の TSV を比較し、ディレクトリ別行数、`HeaderHelpers+Synthetic*` 合計行数、KIR/Lowering TODO/FIXME 数、`"kk_` リテラル数、`interner.resolve == "..."` 数の悪化がないことも確認する（ベースラインは [`docs/refactoring-metrics.md`](docs/refactoring-metrics.md)）。意図的に悪化を許容する場合は、PR 本文に理由・影響範囲・フォローアップ TODO を明記する。

## バグ発見時の対応

作業中に発見したコンパイラ / ランタイムのバグは、TODO.md には追記せず、その場で修正する。修正後は通常の変更と同様にテストを通し、コミット/PR 化する。

- 現在のタスクと無関係、または規模が大きく即時修正が難しい場合のみ、spawn_task で別セッションに切り出す
- 単なるコードの臭いや低確信度の推測は報告不要（spawn_task 自体のガイドラインに準拠）

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
