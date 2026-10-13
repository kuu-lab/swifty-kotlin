# インクリメンタルコンパイル

KUU-1964 の評価として、既定オフを維持し、CLI の明示的な利用導線を整備する。
調査基点は 2026-10-13、master `a1ad746b646afab1ccb242033740e0c6528979e0`。
実装の根拠は [Driver.swift](../Sources/CompilerCore/Driver/Driver.swift)、
[IncrementalCompilationCache.swift](../Sources/CompilerCore/Driver/IncrementalCompilationCache.swift)、
[IncrementalFrontendState.swift](../Sources/CompilerCore/Driver/IncrementalFrontendState.swift)、
[SemaPhase.swift](../Sources/CompilerCore/Sema/Infrastructure/SemaPhase.swift)。

## 利用方法

```bash
# 同一入力・設定で繰り返すと no-op 出力復元の対象になる
.build/debug/kswiftc --incremental hello.kt -o hello
.build/debug/kswiftc --incremental hello.kt -o hello

# 保存先を自分で管理する場合（このオプション単独で有効化）
.build/debug/kswiftc --incremental-cache .build/hello-cache hello.kt -o hello

# 保存先指定や有効化 flag があっても、指定順に関係なく無効化する
.build/debug/kswiftc --incremental-cache .build/hello-cache --no-incremental hello.kt -o hello
```

`-Xfrontend incremental` も引き続き利用可能。CompilerCore API では
`incrementalCachePath` または `incremental` frontend flag で有効化し、
`no-incremental` frontend flag が両方に優先する。
`--no-incremental` は今回の実行でキャッシュを読み書きしない。既存キャッシュは削除しない。

保存先未指定時は Foundation のユーザー caches directory 配下の
`kswiftk/incremental/<namespace>` を使う。macOS では通常
`~/Library/Caches/kswiftk/incremental/`。namespace は出力側の repository identity、
`CompilerBuildInfo.version`、解決済み入力パス集合に基づく。
明示的な保存先はキャッシュ専用ディレクトリにする。保存時に所有者専用権限へ変更される。
信頼できない場所・認証不一致・互換性のない状態はキャッシュミスとなり、通常コンパイルへ戻る。

容量上限・自動 GC・クリア専用 CLI は現在ない。ディスク使用量を監視し、コンパイル停止中に
自分で指定したキャッシュ専用ディレクトリ、または不要な managed namespace を削除する。
managed cache の `incremental-cache.key` は認証鍵であり、削除すると既存キャッシュが再利用できなくなる。

## 再利用の範囲

| 状況・経路 | 現在の動作 |
|---|---|
| 完全な no-op | LoadSources と fingerprint/設定検証後に最終出力を復元。Lex〜Link を省略 |
| 局所変更 | 依存グラフで再コンパイル集合を決定。未変更ファイルの AST/interner を復元し Lex/Parse/BuildAST の仕事を削減。Sema/KIR/Lowering/backend は実行 |
| 局所変更時に frontend state を復元できない | 全ファイルを再コンパイル。no-op 出力復元成功時は frontend state を読まない |
| `--test` | 生成 runner のメモリ内 overlay はキャッシュ対象外 |
| LSP | `runFrontend` の別経路。キャッシュ準備・復元・保存を実行しない |
| Golden | コンテキストを直接構築して各フェーズを実行。Driver の出力キャッシュ対象外 |
| diff_kotlinc | candidate の CLI 呼び出しなので明示的に有効化可能。ただし通常の1回実行では cold cache コストが加わる |

diff_kotlinc は毎回出力を新しい一時ディレクトリへ置くため、`--incremental` だけでは
managed namespace も毎回変わり再利用できない。単一ケースの反復調査では既存の
flag 転送と固定の明示的な保存先を組み合わせる。

```bash
DIFF_KSWIFTC_FLAGS='--incremental-cache /tmp/kswiftk-hello-cache' /opt/homebrew/bin/bash Scripts/diff_kotlinc.sh Scripts/diff_cases/hello.kt
```

キャッシュを使った実行では backend が省略され得るため、回帰ゲート・変更後の検証では
`DIFF_KSWIFTC_FLAGS='--no-incremental'` とするか、有効化 flag を渡さない。
Golden と LSP に flag を追加するだけでは高速化できない。診断と semantic context の
再構築・未保存 buffer の fingerprint を含めた別の設計が必要。

## 既定有効化を見送る理由

現在の build configuration hash は target、最適化、debug、入力順、module、emit、
検索パス、リンク指定、出力へ影響する frontend/IR/runtime flag、stdlib manifest hash、
entry point、frontend state schema を含む。`incremental`、`no-incremental`、
`time-phases`、`jobs=` は出力へ影響しないとして除外する。
しかし、これだけでは既定有効化に必要な条件を満たさない。

* compiler namespace の識別子は固定 `CompilerBuildInfo.version = "0.1.0"`。
  同じ version/schema の実装変更を区別するバイナリ fingerprint はない。
* 環境変数、SDK/リンカ/ランタイムの実体、`-I` の依存 artifact や `-L`/`-l` の
  ライブラリ内容を build configuration hash に取り込んでいない。
  stdlib についても advertised manifest hash とパスを使い、artifact 全体の内容 digest ではない。
* 保存する frontend state は AST/interner であり、警告や Sema context を保存しない。
  no-op 出力復元では前回の警告が再表示されない。
* artifact は設定 hash ごとに蓄積し、容量・保持期間の上限がない。
  複数プロセスによる同一 cache の更新を世代単位で排他する仕組みもない。
* 局所変更後も Sema 以降は実行される。「Lex〜Sema が全て skip」ではない。

既定有効化の前には compiler と外部依存の内容 fingerprint、診断の再表示、
世代単位の整合性・排他、容量上限と GC が必要。GC はまず namespace 単位の
最終利用時刻・保持期間・総容量に基づく削除を設計し、使用中の世代と認証鍵を保護する。
CI の比較検証を無効化可能にした上で、既定 stdlib artifact/native executable、
依存 artifact 更新、コンパイラ更新、SDK/環境変更、長期反復編集を計測・検証してから再判断する。

## 再現可能な計測

```bash
swift build
python3 Scripts/measure_incremental_compile.py --report-dir /tmp/kuu-1964-none
python3 Scripts/measure_incremental_compile.py --stdlib-mode source --report-dir /tmp/kuu-1964-source
```

32ファイル × 8関数と、別ファイルの関数を参照する main を生成し、3反復の中央値を取る。
各反復で通常コンパイル、cold incremental、no-op、1関数の本体変更、変更後の通常コンパイルを測る。
保存先は反復ごとに新しくし、no-op 前には出力を削除して artifact 復元を確認する。
phase log も検査し、no-op は LoadSources のみ、それ以外は Sema 実行を必須とする。
通常/cold/no-op の KIR は完全一致を確認し、局所変更後は古い出力でないことを確認する。
全256関数の返却定数も検査し、変更した関数が `42` を返し、未変更関数の値が保持されることを確認する。
局所変更の incremental/full KIR は AST ID が異なる可能性があるため両方を保存して検査する。
JSON に実時間・キャッシュ容量・出力 SHA-256、stderr に phase timing を保存する。
1回のコンパイルのタイムアウトは既定300秒で、`--compile-timeout` で変更できる。
タイムアウトは未完了として記録し、有効な測定値として集計しない。
`TOTAL` は cache 読み込み・保存や Driver の KIR 出力を全て含む実時間ではないため、
主要な比較には subprocess の wall time を使う。

この計測は `--emit kir` のフロントエンド評価で、native executable の Link 時間・
既定 `.kklib` の挙動・大規模プロジェクト全般の性能を保証しない。

### ローカル観測（2026-10-13）

macOS arm64、Apple Swift 6.4 (`swiftlang-6.4.0.30.4`)、debug ビルド。
上記の32ファイル、stdlib なし、3反復の wall time は次のとおり。
同一ホストで他 worktree の Swift ビルドが多数動作しており、絶対時間・倍率は
負荷の影響を受ける参考値である。no-op でも51〜721msのばらつきがあった。

| ケース | 中央値 | 範囲 |
|---|---:|---:|
| 通常 | 2.43s | 2.15〜2.60s |
| cold incremental | 6.64s | 4.86〜7.79s |
| no-op incremental | 0.64s | 0.05〜0.72s |
| 局所変更 incremental | 9.74s | 7.64〜12.59s |
| 同じ局所変更の通常コンパイル | 2.08s | 1.97〜2.82s |

no-op は全3反復で LoadSources のみ実行し、削除済み KIR を復元した。
通常/cold/no-op の出力は完全一致。局所変更 incremental/full も全3反復で
KIR が完全一致し、全256関数の返却定数を検査した。
cache は cold 約0.66MiB、1回の局所変更後に約0.69MiB。
局所変更時の LoadSources（fingerprint・frontend state 復元を含む）の中央値は4.05sで、
Sema 以降も実行された。少なくともこの入力では局所変更を高速化できず、
cache 読み込み・保存を含む実時間の改善を別途評価する必要がある。
wall time から phase timing の合計を引いた時間も、cold で中央値4.39s、局所変更で3.74sあった。
この差にはプロセス起動・cache の初期ロード・保存・KIR 出力が含まれ、個別処理への
帰属はまだ測定していない。phase の `TOTAL` だけで効果を判定しない。

同じ32ファイルの `--stdlib-mode source` 計測も試行したが、最初の通常コンパイルが
300秒でタイムアウトし、cold/no-op/局所変更の測定へ到達しなかった。
多数の他ビルドに加え、途中から対象テストのビルドも同一ホストで実行したため、
stdlib 注入経路は未評価とする。タイムアウトを成功や性能改善の根拠には使わない。

## 変更の検証範囲

`swift build` 成功後、以下の対象ゲートを実行して57テストが成功した。

```bash
/opt/homebrew/bin/bash Scripts/swift_test.sh \
  --filter 'KSwiftKCLITests.CLIParserTests|CompilerCoreTests.DriverIncrementalTests/testExplicit|CompilerCoreTests.IncrementalCompilationCacheTests' \
  --no-parallel
```

内訳は CLIParserTests 22件、Driver の追加2件、IncrementalCompilationCacheTests 33件。
追加 Driver テストは、保存先指定だけで有効化・出力復元できることと、無効化時に
変更後のソースをコンパイルし、既存キャッシュを更新せず新しいキャッシュも作らないことを確認する。
計測スクリプトの最終版は2ファイル・1反復の全5経路と、短いタイムアウトによる未完了記録を確認した。
`git diff --check` も成功。全 Swift テスト、全 Golden、全 diff、native executable の
キャッシュ復元、CI は未実行であり、この対象ゲートの成功に含めない。
