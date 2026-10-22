# インクリメンタルコンパイル

KUU-1964 で実装と opt-in の CLI 制御を導入し、KUU-2678 で安全性を満たす範囲に限定して
既定有効化した。実装の根拠は [Driver.swift](../Sources/CompilerCore/Driver/Driver.swift)、
[IncrementalCompilationCache.swift](../Sources/CompilerCore/Driver/IncrementalCompilationCache.swift)、
[IncrementalFrontendState.swift](../Sources/CompilerCore/Driver/IncrementalFrontendState.swift)、
[IncrementalEnvironmentFingerprint.swift](../Sources/CompilerCore/Driver/IncrementalEnvironmentFingerprint.swift)、
[SemaPhase.swift](../Sources/CompilerCore/Sema/Infrastructure/SemaPhase.swift)。

## 既定範囲

既定で有効なのは、出力がネイティブ系 emit（executable / library / object / KIR 等）かつ
stdlib artifact（`.kklib`）または `--no-stdlib` でコンパイルする場合。
次は引き続き opt-in（`--incremental` / `--incremental-cache` が必要）または無効。

| 構成 | 既定 |
|---|---|
| `stdlibLibraryPath` または解決済み既定 `.kklib` を使うネイティブ emit | 有効 |
| `--no-stdlib` | 有効 |
| bundled stdlib ソース注入（`--stdlib-from-source` 等、`includeStdlib` 解決後） | 無効 |
| `--stdlib-only` | 無効 |
| JVM 出力（`--emit jar` 等、`emit.isJVM`） | 常に無効（明示 flag でもオフ） |

bundled stdlib のソース注入は全 stdlib AST を frontend state に直列化することになり、
キャッシュが純粋なコストになるため既定対象外。JVM 出力はフロントエンド状態の再利用を
検証していないため常に無効。

## 利用方法

```bash
# 既定: ネイティブ + stdlib artifact 構成では指定なしで有効
.build/debug/kswiftc hello.kt -o hello
.build/debug/kswiftc hello.kt -o hello   # 2 回目は no-op 復元の対象

# 既定対象外の構成、または保存先を自分で管理する場合
.build/debug/kswiftc --incremental hello.kt -o hello
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

容量管理は自動。`artifacts/` 配下の設定世代は namespace ごとに最大 8 件まで残り、
それを超えた古い世代（60 秒より古いもの）は保存時に削除する。managed namespace 全体は
manifest の最終更新から 30 日経過すると、別のコンパイルの保存時にまとめて削除する。
managed cache の `incremental-cache.key` は認証鍵であり、削除すると既存キャッシュが
再利用できなくなる。

## ヒット率の可視化

```bash
# 実行ごとの結果を stderr に出力（restored=完全復元、partial=部分再利用、full=全ビルド）
.build/debug/kswiftc -Xfrontend incremental-stats hello.kt -o hello
# incremental: runs=3 restored=2 partial=0 full=1 hit-rate=66%
```

`time-phases` と併用すると、キャッシュ検証・復元のコストが `LoadSources` 内の
`incremental-prepare` サブフェーズとして表示される。統計は `stats.json` に永続化され、
連続実行の累積値が出る。

## 再利用の範囲

| 状況・経路 | 現在の動作 |
|---|---|
| 完全な no-op | LoadSources と fingerprint/設定検証後に最終出力を復元。Lex〜Link を省略 |
| 局所変更 | 依存グラフで再コンパイル集合を決定。未変更ファイルの AST/interner を復元し Lex/Parse/BuildAST の仕事を削減。Sema/KIR/Lowering/backend は実行 |
| 局所変更時に frontend state を復元できない | 全ファイルを再コンパイル。no-op 出力復元成功時は frontend state を読まない |
| `--test` | 生成 runner のメモリ内 overlay はキャッシュ対象外 |
| LSP | `runFrontend` の別経路。キャッシュ準備・復元・保存を実行しない |
| Golden | コンテキストを直接構築して各フェーズを実行。Driver の出力キャッシュ対象外 |
| diff_kotlinc | candidate の CLI 呼び出し。既定範囲の emit では managed cache に保存するが、出力先が毎回変わるため再利用されない。nightly CI は `--no-incremental` を渡して保存コスト自体を省く |

diff_kotlinc は毎回出力を新しい一時ディレクトリへ置くため、既定有効化でも
managed namespace は毎回変わり再利用できない（保存コストのみ残る）。単一ケースの
反復調査では既存の flag 転送と固定の明示的な保存先を組み合わせる。

```bash
DIFF_KSWIFTC_FLAGS='--incremental-cache /tmp/kswiftk-hello-cache' /opt/homebrew/bin/bash Scripts/diff_kotlinc.sh Scripts/diff_cases/hello.kt
```

キャッシュを使った実行では backend が省略され得るため、回帰ゲート・変更後の検証では
`DIFF_KSWIFTC_FLAGS='--no-incremental'` とする（flag 不指定でも既定範囲の emit では
キャッシュが有効な点に注意）。
Golden と LSP に flag を追加するだけでは高速化できない。診断と semantic context の
再構築・未保存 buffer の fingerprint を含めた別の設計が必要。

## KUU-2678 で解消した既定有効化の阻害要因

KUU-1964 時点の調査で既定オフを維持した根拠と、その後の対応は次のとおり。

* compiler バイナリの fingerprint がない → 実行ファイルの real path・size・mtime・
  inode・権限の stat signature を environment fingerprint に追加し、同じ version の
  別ビルドは別の build configuration としてキャッシュミスになる。
* 環境変数・SDK/リンカ/ランタイム・`-L`/`-l`・`.kklib` の内容が hash 外 →
  `IncrementalEnvironmentFingerprint` が toolchain 解決系の環境変数（`PATH`、
  `DEVELOPER_DIR`、`SDKROOT`、`DYLD_*`、`KSWIFTK_*`、`SWIFT_*` 等）、PATH 上の
  `swift`/`swiftc`/`clang`/`dsymutil` の実体、検索パス配下の `.kklib`
  manifest hash と object signature、`-L` で解決される `lib<name>.{so,a,dylib,tbd}`
  の signature を hash に畳み込む。executable emit ではさらに backend provider が
  packaged runtime objects と linker plan identity（`MacOSLinkerPlan.cacheIdentity`）
  を追加する。
* no-op 復元で警告が再表示されない → 非 error 診断を `diagnostics.json` に保存し、
  出力復元時に replay する。
* 容量上限・GC がない → 設定世代は namespace ごと 8 件、managed namespace は
  manifest の最終更新から 30 日で掃除する。
* no-op 検証がフルコンパイルより遅い → キャッシュ整合性の SHA-256 を
  バッファ処理に書き換え（CryptoKit がある環境ではそれを使用）、
  environment fingerprint と configuration hash をプロセス内で memoize した。

残る既知の範囲: 局所変更後も Sema 以降は実行される（「Lex〜Sema が全て skip」ではない）。
複数プロセスが同一 cache を同時更新した場合の世代単位の排他はないが、世代名は
build configuration hash で分かれており、新しい世代が 60 秒の prune 猶予を持つため
並行コンパイルが書いた直後の出力を掃除しない。認証不一致・互換性のない状態は
常にフルビルドへ戻る。

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

## 変更の検証範囲（KUU-2678）

対象ゲートとして次を実行した（同一ホスト上に多数の並行ビルドがあり、時間は
負荷の影響を受ける参考値）。

```bash
swift build
swift test --no-parallel --filter \
  'DriverIncrementalTests|FileFingerprintTests|IncrementalEnvironmentFingerprintTests|IncrementalCacheSecurityTests|CLIParserTests'
swift test --no-parallel --filter 'IncrementalCompilationCacheTests|FrontendPhasesTests'
```

第1バッチは 52 テスト。既定有効化（managed cache・`--no-incremental` 優先・
bundled stdlib ソース注入の既定除外・JVM 無効化・警告 replay・stats・世代 prune）と
SHA-256 既知ベクトル（empty / "abc" / 56B 2ブロック / 64B 境界 / 1MB）を追加した。
`testIncrementalStatsRecorded` だけが初回実行で失敗した。cold run が
cache ディレクトリ作成前に結果を記録して落としていたため `recordOutcome` で
`ensureSecureLocation` 経由の作成を許す修正を入れ、単体で再実行して成功した。
第2バッチは 53 テスト全件成功（IncrementalCompilationCacheTests 33 +
FrontendPhasesTests 20）。

実機計測（macOS arm64、debug、`hello.kt` → native executable、stdlib artifact 解決済み）:

- 1 回目（cold / バイナリ fingerprint 変更直後）: full build。`incremental: runs=1 full=1`。
- 2 回目以降（no-op）: `incremental: runs=2 restored=1 hit-rate=50%`。
  `incremental-prepare` は 232〜1023ms（負荷下の wall）、user CPU は約 0.36s。
  KUU-1964 時点のスカラー SHA-256 では no-op がフルビルドより遅かったが、
  CryptoKit への移行で検証コストを解消した。
- `--emit kir` の fresh / restore 出力は SHA-256 が一致することを確認した
  （`c5c29bb4…` 両ランで一致）。
- コンパイラバイナリの再ビルドで全てのランが full になること（binary signature
  invalidation）も観測した。

全 Swift テスト、全 Golden、`diff_kotlinc.sh` の全ケース、stdlib 差替え・
環境差替えの E2E invalidation は未実行であり、対象ゲートの成功に含めない。
nightly CI の diff 系ジョブには `--no-incremental` を渡すようにした。

## 宣言単位の依存グラフ（KUU-2810、第1段階）

ファイル単位の `DependencyGraph` に加えて、トップレベル宣言単位の `DeclarationDependencyGraph`
（[DeclarationDependencyGraph.swift](../Sources/CompilerCore/Driver/DeclarationDependencyGraph.swift)、
[DeclarationGraphBuilder.swift](../Sources/CompilerCore/Driver/DeclarationGraphBuilder.swift)）を
`deps.json` に永続化する。`-Xfrontend incremental-stats` で
`declarations: total=N invalidated=M` を stderr に出す（前回との差分で再処理が必要な宣言数）。

* hash は**ソーステキスト**由来（SymbolID・arena 添字を使わない）で、無関係な編集に影響されない。
* 関数は signature / body を分離。ただし `inline`、戻り型省略の式本体（推論型が呼び出し側に見える）は
  body も signature に含める。クラス・プロパティ等は全文を両 hash とする。
* 参照は「宣言済み単純名が識別子として現れる」過剰近似。`plus`/`get`/`invoke` 等の演算子規約名は
  構文上名前が現れないため全宣言の参照に含める。
* signature 変更は直接の依存元のみを無効化し、依存元の signature が変われば連鎖する。
* `ContentAddressedStore` は破損検出（ペイロード SHA-256）・原子的書き込み・所有者/symlink 検査付きの
  content-addressed 保存先。`DeclarationDependencyGraph.cacheKey(for:environment:)` が宣言単位のキーを返す。

**未実装（この段階の範囲外）**: 宣言単位で Sema/KIR/LLVM の仕事を実際にスキップする経路。
`hello.kt`（stdlib `.kklib` 使用、debug）の計測ではバックエンド（emit/opt/write）は合計数十 ms で、
時間の約 99% は `DataFlowSema`（stdlib import）だった。ユーザーコードのバックエンド結果を
キャッシュしても現状は効果が測れず、一方 `declareExternalFunction` の名前共有キャッシュや
partition の extern 宣言が全関数に依存するため、キー設計を誤ると誤コンパイルになる。
実際にスキップするには、(1) 宣言単位の Sema 結果の直列化、(2) KIR 関数の SymbolID 正規化、
(3) 全体最適化と整合する object 単位のリンク設計が必要。
