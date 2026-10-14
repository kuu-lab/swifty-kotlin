# Sema body worker の所有権分離（KUU-2000）

2026-10-14。#8864 の独立 scalar 本体に続く変更。local / lambda / object の
共有状態を先に分離し、通常呼び出しの対応はこの段階に含めない。
KUU-2000 全体の完了ではなく、既定は引き続き直列である。

## 所有権の境界

`SemaBodyWorker` は module barrier で AST、SymbolTable、TypeSystem、StringInterner を
COW snapshot にし、新しい診断、solver、resolver、data-flow、cache、driver/delegate を
作る。TypeSystem の symbolTable は worker 側へ付け替える。file/import scope と
source data は join まで読み取り専用。lazy imported metadata loader がある module は
本番 body worker を開始しない。

BindingTable は closed delta 用の空のテーブル、または全 side table の値 snapshot を
選べる。後者は capture、callable-reference、annotation の検証済み marker と遅延対象、
cached union を含む。snapshot を作れることと、その結果を module にマージできることは
別の契約である。lambda/object の一般的な snapshot 結果を本番へ採用しない。

inferred return/property の context と checking/checked/deferred 帳簿は module driver に
残す。context をそのままコピーすると parent の Sema、scope、resolver 等への参照も
worker に入ってしまう。contract 先行収集、constructor initializer と inferred property
固定点反復を完了してから、依存推論を必要としない本体だけを開始する。

監査で見つかった既存 snapshot のコピー漏れも補った。

* SymbolTable: setter visibility、imported stdlib symbol の識別。
* TypeSystem: nominal type parameter の upper bounds、capture の次 ordinal。
  capture ordinal をリセットすると新しい existential が snapshot 内の既存型と同一に
  intern される。worker ごとの独立採番を保ち、captured type の一般的な join は未対応。
* scalar delta の拒否条件: callable reference、annotation factory、primary-constructor
  annotation、検証済み opt-in marker、pending local annotation target、body expression 外の
  source-declared expected-type marker。local 型 annotation が付ける marker は、その宣言本体
  の ExprID に属する分だけ結果へ含めて join する。

## 採用できる local delta

| 本体 | snapshot の独立実行 | 本番 join |
| --- | --- | --- |
| 既存の独立 scalar 式 | 対応 | 対応 |
| scalar local の val/var、単純代入、block、unlabeled return | 対応 | 対応 |
| scalar local の型 annotation（初期化子あり） | 対応 | 対応 |
| delegate / lateinit、local function / nominal | snapshot の格納対象（一般的な意味一致は未検証） | 直列 |
| lambda の負の合成 parameter SymbolID、capture、callable-value call | 所有権テストで確認 | 直列 |
| object literal の nominal/member/backing symbol、capture、pending annotation | 所有権テストで確認 | 直列 |
| inferred 依存、通常呼び出し、lazy metadata | module 帳簿・loader の契約が必要 | 直列 |

新しい対象も明示戻り型、non-null primitive/String 引数、非 generic、receiver なしの
top-level 関数に限る。scalar local は initializer を必須とし、resolved symbol が scalar
型であることを join 前に確認する。delegate と `lateinit` は除外する。worker が実際に
作った symbol がすべて `.local` で scalar 型を持ち、
識別子の解決先が現在の関数の引数または新規 local であることを確認する。後から宣言される
local と同名の module property を読んだ場合も、解決先の確認で採用しない。

local delta は宣言ごとの差分だけを保存する。同じファイルの先行関数の local を後続の
結果へ再添付しない。helper が intern した文字列を含む string delta も宣言単位で保存し、
file/decl 順に intern し直す。local の FQName は `__local_<ExprID>` と source name なので
worker SymbolID を埋め込まない。型を canonicalize した後で local symbol を登録し、
identifier binding の SymbolID と expr binding の TypeID を対応表で書き換える。
間に直列の lambda/object 本体が ordinal を消費しても、worker の raw ordinal を流出させない。

診断、新規 non-local symbol、未対応 side table が出たファイルは全結果を破棄し、module
driver が元の宣言順で再検査する。抑制と rollback は worker-local で扱い、件数上限は
module の直列再検査時に適用する。
large stack、jobs 上限、indexed join、失敗時の全 task join は既存 runner を使う。

## 次の契約

lambda を採用するには、負の parameter/receiver SymbolID に付いた property type と
capture/return/callable-value/SAM 等の副表を完全にマージする必要がある。object は
nominal metadata、parent graph、signature、backing/delegate/accessor symbol、AST の
追加・変更と pending annotation を含む。生成名に SymbolID を埋め込む箇所があるため、
文字列の単純再 intern だけでは一般的な object delta の決定性を保証できない。

本体を snapshots に移しただけで汎用 per-file 並列化を有効にせず、この契約を別の変更で
固定する。snapshot は task 内で作って結果抽出後に解放し、同時保持数を jobs 以下にする。
全ファイル分の driver を dispatch 前に保持しない。worker 間で可変 snapshot を再利用する
最適化は別の契約として残す。

## 検証の再実行

```bash
swift build --disable-sandbox -j 4
SWIFT_TEST_PRODUCT=CompilerCoreTests SWIFT_TEST_BUILD_JOBS=4 \
  /opt/homebrew/bin/bash Scripts/swift_test.sh --disable-sandbox --no-parallel \
  --filter 'SemaIndependentBodyTests|SemaBodyWorkerOwnershipTests|SemaPerFileExecutorTests'
python3 Scripts/benchmark_sema_independent.py --body locals --files 10 50 \
  --functions 4 --terms 8 --jobs 1 2 4 --runs 3 > /tmp/sema-ownership.tsv
python3 Scripts/benchmark_sema_independent.py --body typed-locals --files 10 50 \
  --functions 4 --terms 8 --jobs 1 2 4 --runs 3 > /tmp/sema-typed-locals.tsv
python3 Scripts/validate_sema_worker_ownership.py --output /tmp/sema-ownership-gate
```

benchmark の TSV には `body` 列を追加した。過去の scalar 測定 TSV は過去の列形式のまま
保存する。flag off/on と jobs=1/2/4、wall time と process peak RSS を比較し、source と
fresh artifact の経路・O0/O2 の実行と KIR は別に比較する。artifact の直列 fallback を
body 並列化の成功として数えない。

`validate_sema_worker_ownership.py` は空の出力ディレクトリを要求し、現 compiler で stdlib
artifact を新規生成する。型注釈付き scalar locals と、間に直列で検査する lambda/object
capture を含む 2 ファイルで、12 executable compile/run の stdout と 12 KIR compile の jobs 間
raw 一致（8 比較）を確認する。KIR 比較では一時パスと行末空白だけを正規化し、ID を保持する。
worker が採用された件数は上記 Swift テストで別に確認する。

BuildAST の file-local arena と順序付き merge で並列採番を決定的にした
[KUU-2140 / #8962](https://github.com/kuu-lab/swifty-kotlin/pull/8962) が master に入った。
現行の CLI 検証では `validate_sema_worker_ownership.py` が一時パスと行末空白だけを正規化し、
lambda 名・負の SymbolID を含む raw KIR を jobs=1/2/4 で比較する。ID の置換はしない。
Swift の固定 AST 比較では raw TypeID/SymbolID/FQName/interner も引き続き確認する。

## 今回の確認結果（2026-10-15）

macOS arm64、Apple Swift 6.4、debug compiler。作業ブランチを master
`b72569983af5c58ad5aa3ae9657c3d44de0d5a14` へ fast-forward してから確認した。

* `swift build --disable-sandbox -j 4` が exit 0。
* `SemaIndependentBodyTests|SemaBodyWorkerOwnershipTests|SemaPerFileExecutorTests` の
  対象3 suites は 23 tests が成功。明示型付き scalar local の canonical binding join、
  不正な local annotation の直列 fallback、marker の body ExprID 範囲制約と、既存の
  jobs=1/2/4 の決定性・所有権・依存バリアを検証した。
* 両 Python スクリプトの AST 構文解析と `git diff --check` が成功。
* fresh artifact の source/artifact・O0/O2・jobs=1/2/4 検証は、master fast-forward 前の
  `4ccde1383e42d8f538c399c1b0c5769267f9ecdd` で成功済み（12 executable compile/run、12 KIR
  compile、8 raw KIR 比較）。master fast-forward 後は未再実行のため、最新 base でのこのゲートは
  未確認。
* Thread Sanitizer、全テスト、全 Golden、kotlinc diff、Linux / Swift 6.3、release compiler
  は今回の更新では未実行。

## local 本体の参考測定

上記 benchmark の stdlib=none、各ファイル 4 関数、8 terms の initializer と 2 locals、
debug compiler。flag off/on × jobs=1/2/4 の各構成で warmup を除く 3 標本を採取した。
計測中に本作業の build/test/source-artifact gate は重ねていない。外部の host 負荷は
管理していないため、通常負荷や release の性能を示すものではない。
先行する `locals` 144行と、2026-10-14 に追加した `typed-locals` 144行を
[生 TSV](sema-worker-ownership-measurements.tsv) に保存した。

以下は jobs=4 の中央値。Sema の時間と各 sub-phase の中央値は足し合わせない。
RSS は compiler process 全体の最大値で、Sema 単独のメモリではない。

| files | flag | Sema ms | type-check ms | peak RSS MiB |
| --- | --- | ---: | ---: | ---: |
| 10 | off | 42.96 | 7.81 | 28.89 |
| 10 | on | 44.46 | 9.34 | 29.61 |
| 50 | off | 88.12 | 36.98 | 46.36 |
| 50 | on | 95.57 | 44.29 | 47.05 |

この条件でも高速化は確認できなかった。snapshot の同時保持と local delta の累積は
抑えたが、準備・snapshot 構築・canonical join のコストが残る。既定有効化、一般的な
lambda/object の join、コア数に比例する高速化、KUU-2000 の完了は主張しない。

型注釈付き local の追加経路は、2026-10-14 に Swift 6.4 / arm64 / debug compiler、
stdlib=none、1 warmup + 3標本で測定した。各ファイルは4関数、8個の `x * x` 項を持つ。
ホスト負荷は管理していない。jobs=4 の中央値は次のとおりで、型 annotation を含む worker
経路でも高速化は見られなかった。

| files | flag | Sema ms | type-check ms | peak RSS MiB |
| --- | --- | ---: | ---: | ---: |
| 10 | off | 52.82 | 14.41 | 27.89 |
| 10 | on | 83.91 | 18.64 | 30.59 |
| 50 | off | 106.23 | 48.09 | 46.25 |
| 50 | on | 137.95 | 79.91 | 47.19 |

この測定は候補範囲の代表性・通常負荷の性能を示さない。Sema worker は引き続き明示 opt-in
のままにする。

全テスト、全 Golden、全 kotlinc diff、Linux / Swift 6.3、release compiler は未実行。
