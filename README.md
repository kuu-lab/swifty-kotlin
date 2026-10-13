# KSwiftK

**KSwiftK** は Swift で書かれた Kotlin コンパイラです。Kotlin 2.3.10 stable の機能をターゲットとし、LLVM 経由で macOS ネイティブ実行ファイルを生成します。

| 属性 | 値 |
|---|---|
| 実装言語 | Swift 6.2 (Swift language mode 6) / macOS 12+ |
| ビルドシステム | SwiftPM |
| 出力バイナリ | `kswiftc` |
| ターゲット | Kotlin 2.3.10 stable, macOS arm64/x86_64 |

---

## クイックスタート

```bash
# ビルド
swift build

# コンパイル & 実行
.build/debug/kswiftc hello.kt -o hello
./hello
```

反復コンパイルでは `--incremental` でキャッシュを明示的に有効化できます（既定はオフ）。
保存先を管理したい場合は `--incremental-cache <path>`、一時的に無効化する場合は
`--no-incremental` を指定します。利用例・計測結果・既定有効化の判断は
[`docs/incremental-compilation.md`](docs/incremental-compilation.md) を参照してください。

---

## ビルド & テスト

```bash
swift build                    # デバッグビルド
swift build -c release         # リリースビルド

bash Scripts/swift_test.sh                             # 全テスト（並列）
bash Scripts/swift_test.sh --filter SmokeTests         # スモークテストのみ
bash Scripts/swift_test.sh --filter Golden # ゴールデンテストのみ（Swift Testing）

UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden  # ゴールデン更新
bash Scripts/diff_kotlinc.sh Scripts/diff_cases        # kotlinc との差分回帰テスト
```

---

## コンパイルパイプライン

```
LoadSources → Lex → Parse → BuildAST → SemaPasses → BuildKIR → Lowering → Codegen → Link
```

詳細は [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) を参照してください。

---

## ドキュメント

| ファイル | 内容 |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | アーキテクチャ詳細・ディレクトリマップ・タスク別ナビゲーション |
| [`docs/spec.md`](docs/spec.md) | フェーズ別実装仕様（Swift 型・API レベル） |
| [`docs/debugging.md`](docs/debugging.md) | DWARF デバッグ情報の使い方（lldb セッション例） |
| [`docs/kotlin-test-runner.md`](docs/kotlin-test-runner.md) | `--test` で kotlin.test の注釈からテスト実行ファイルを生成 |
| [`docs/incremental-compilation.md`](docs/incremental-compilation.md) | インクリメンタルコンパイルの利用方法・計測・既定有効化の判断 |
| [`docs/real-program-round3-tracking.md`](docs/real-program-round3-tracking.md) | 公開 Kotlin 実プログラム第3弾の子チケット・PR・検証不足・原本残障害の追跡 |
| [`TODO.md`](TODO.md) | 未完了タスク一覧 |
| [`AGENTS.md`](AGENTS.md) | AI 向けクイックリファレンス・Linux（Cursor Cloud）環境セットアップ |
