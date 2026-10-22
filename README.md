# KSwiftK

**KSwiftK** は Swift で書かれた Kotlin コンパイラです。Kotlin 2.4.20 stable の機能をターゲットとし、LLVM 経由で macOS ネイティブ実行ファイルを生成します。

| 属性 | 値 |
|---|---|
| 実装言語 | Swift 6.2 (Swift language mode 6) / macOS 12+ |
| ビルドシステム | SwiftPM |
| 出力バイナリ | `kswiftc` |
| ターゲット | Kotlin 2.4.20 stable, macOS arm64/x86_64 |

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

開発中に常駐コンパイルプロセスを利用するには、別のターミナルで daemon を起動してから
`--watch` で入力ファイルを監視します。daemon はデコード済み kklib index、import 済み bundled stdlib の
`SymbolTable` / `TypeSystem` snapshot、LLVM context を保持します。snapshot は各要求で copy-on-write 分岐し、
ユーザー宣言は要求間で共有しません。初回 import 後に stdlib metadata を materialize して再利用可能な状態を作ります。
この Sema snapshot の対象は bundled stdlib artifact のみで、追加の `-I` library がある場合は通常の import 経路を使います。

```bash
# Terminal 1
.build/debug/kswiftc --daemon

# Terminal 2
.build/debug/kswiftc --watch hello.kt -o hello
```

通常のコンパイルコマンドも起動中の daemon があれば接続し、なければ従来どおり直接コンパイルします。
`--watch` はネイティブ出力で incremental compilation を自動的に有効にします。daemon は Ctrl-C で停止できます。
socket の場所を変更する場合は `KSWIFTK_DAEMON_SOCKET` を設定してください。

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

実験的な JVM M22 出力は `kswiftc --emit class|jar hello.kt -o <出力先>` で利用できます。
変数・数値演算・関数・条件分岐・ループに加え、クラス・コンストラクタ・プロパティ・継承・interface、ジェネリクス・配列・基本コレクション・例外処理、ラムダ・クロージャ・高階関数・拡張関数に対応しています。
`--classpath deps.jar` による外部 JVM 呼び出しと、Java／公式 Kotlin 向けライブラリ JAR 生成にも対応します。
SAM 変換・inline 展開・suspend 関数にも対応します。
object・companion object・data class・enum class・sealed classと、網羅的なwhenにも対応します。
匿名object・data object・inner class、名前付き引数・デフォルト引数にも対応します。
クラス委譲・委譲プロパティ・lazy・lateinitにも対応します。
value class・typealias・アノテーション・クラス／関数／プロパティのリフレクションにも対応します。
ジェネリックvalue classとrepeatableアノテーション（自動／明示コンテナ）の生成・実行にも対応します。
配列や別のvalue classを保存値に持つvalue class、デフォルト引数・セカンダリコンストラクタにも対応します。
value classを引数・戻り値に持つinline関数・suspend関数にも対応します。
inline suspend関数とreified型パラメータ（型判定・cast・class literal・配列生成・型情報をcaptureするラムダ）にも対応します。
reified関数参照と、匿名objectへのreified型情報のcaptureにも対応します。
Char・Byte・Short・UInt・ULong・UByte・UShortの演算・変換・配列・ボックス化と、Java／公式Kotlin向けABIにも対応します。
Stringの連結・文字列テンプレート・UTF-16での参照／反復・検索・置換・split・trim・大小文字変換・数値変換にも対応します。これらの操作も独自stdlibで実行できます。
Regexの検索・グループ・置換・split、StringBuilder／buildString、文字列のmap・filter・fold・reduce・windowed等にも対応します。実行には独自stdlibを使用できます。
groupBy・associate・partition・zip・joinToString、公式Pair、Sequenceの遅延パイプライン・生成・終端操作にも対応します。
factory・変換・distinct・take/drop・joinToString・Sequenceは独自stdlibで動作します。
`sequence { yield(...) }`／`iterator { ... }`と、Iterator・Iterable・Sequenceを受け取る`yieldAll`にも対応します。
このリポジトリの Kotlin ソースから、対応済みJVM機能のruntimeを含むstdlibを生成できます。

```bash
.build/debug/kswiftc --stdlib-only --emit jar -o kswiftk-stdlib.jar
.build/debug/kswiftc main.kt helpers.kt --emit jar --classpath kswiftk-stdlib.jar -o app.jar
java -Xverify:all -cp app.jar:kswiftk-stdlib.jar MainKt
```

対応済みの文字列・collection・Sequence builder・Regex・unsigned・coroutine・reflection・lazyを、生成物と独自JARだけで実行できます。公式 `kotlin-stdlib.jar`／`kotlin-reflect.jar` の実行時指定は不要です。
実行方法と制限は [JVM バックエンド](docs/jvm-backend.md)、ソースの構成と検証範囲は [JVM stdlib のソース化](docs/jvm-stdlib.md) を参照してください。

| ファイル | 内容 |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | アーキテクチャ詳細・ディレクトリマップ・タスク別ナビゲーション |
| [`docs/spec.md`](docs/spec.md) | フェーズ別実装仕様（Swift 型・API レベル） |
| [`docs/debugging.md`](docs/debugging.md) | DWARF デバッグ情報の使い方（lldb セッション例） |
| [`docs/kotlin-test-runner.md`](docs/kotlin-test-runner.md) | `--test` で kotlin.test の注釈からテスト実行ファイルを生成 |
| [`docs/incremental-compilation.md`](docs/incremental-compilation.md) | インクリメンタルコンパイルの利用方法・計測・既定有効化の判断 |
| [`TODO.md`](TODO.md) | 未完了タスク一覧 |
| [`AGENTS.md`](AGENTS.md) | AI 向けクイックリファレンス・Linux（Cursor Cloud）環境セットアップ |
