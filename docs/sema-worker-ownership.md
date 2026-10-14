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
  annotation、検証済み opt-in marker、pending local annotation target。

## 採用できる local delta

| 本体 | snapshot の独立実行 | 本番 join |
| --- | --- | --- |
| 既存の独立 scalar 式 | 対応 | 対応 |
| scalar local の val/var、単純代入、block、unlabeled return | 対応 | 対応 |
| local の型 annotation / delegate / lateinit、local function / nominal | snapshot の格納対象（一般的な意味一致は未検証） | 直列 |
| lambda の負の合成 parameter SymbolID、capture、callable-value call | 所有権テストで確認 | 直列 |
| object literal の nominal/member/backing symbol、capture、pending annotation | 所有権テストで確認 | 直列 |
| inferred 依存、通常呼び出し、lazy metadata | module 帳簿・loader の契約が必要 | 直列 |

新しい対象も明示戻り型、non-null primitive/String 引数、非 generic、receiver なしの
top-level 関数に限る。通常 local は initializer を必須とし、型 annotation、delegate、
lateinit を除外する。worker が実際に作った symbol がすべて `.local` で scalar 型を持ち、
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
python3 Scripts/validate_sema_worker_ownership.py --output /tmp/sema-ownership-gate
```

benchmark の TSV には `body` 列を追加した。過去の scalar 測定 TSV は過去の列形式のまま
保存する。flag off/on と jobs=1/2/4、wall time と process peak RSS を比較し、source と
fresh artifact の経路・O0/O2 の実行と KIR は別に比較する。artifact の直列 fallback を
body 並列化の成功として数えない。

`validate_sema_worker_ownership.py` は空の出力ディレクトリを要求し、現 compiler で stdlib
artifact を新規生成する。scalar locals と、間に直列で検査する lambda/object capture を
含む 2 ファイルで、12 executable compile/run の stdout と 12 KIR compile の jobs 間
正規化後の一致（8 比較）を確認する。worker が採用された件数は上記 Swift テストで別に
確認する。

既存 BuildAST の parallel append は ExprID を到着順で割り当てるため、`sema-parallel`
を付けない対照でも lambda の合成名と負の合成 SymbolID が jobs 間で変わる。
[KUU-2140](https://linear.app/kuu/issue/KUU-2140) に最小 2 ファイルと flag off の再現を記録した。
Sema の Swift 比較は frontend jobs=1 で AST を固定し、Sema だけ jobs=1/2/4 として
raw TypeID/SymbolID/FQName/interner を比較する。CLI 比較では、この既存 AST 由来の
`kk_lambda_<ExprID>`、adapter 名、parameter/capture namespace の ExprID 部分だけを
対応付ける。通常の SymbolID、TypeID、KIR register、宣言 ID は変更しない。正規化前 KIR、
正規化後 KIR、対応表を保存し、raw KIR の不一致件数も報告する。一般的な raw ID の完全
決定性を検証したとは扱わない。

## 今回の確認結果

macOS arm64、Apple Swift 6.4、debug compiler。開始時と最終確認時の master は
`01544852e570d6bb1766e44b4e9fb47af88121f2`。

* 最終ソースの `swift build --disable-sandbox -j 4` が exit 0。
* 対象 3 suites は 20 tests、parameter 展開後 31 cases が成功。Sema jobs=1/2/4 の
  raw binding/型/採番、診断全内容・順序、fallback、親と sibling の capture/合成
  parameter/property type/AST/診断の隔離を検証した。全 frontend を並列にする
  scalar local の source-position binding 比較も別に確認した。
* 独立した静的レビューで spec、closed delta の採用範囲、全 BindingTable storage、
  並行 snapshot 構築時の凍結 read、jobs 以下の保持と join を確認。
* 別 scratch path の Thread Sanitizer 実行でも同じ 20 tests / 31 cases が成功し、
  競合の診断はなかった。通常ビルドと test build は重ねていない。
* 現 compiler で生成した fresh artifact と source 注入で、O0/O2 × jobs=1/2/4 の
  全 12 executable compile/run が exit 0、stdout は `8\n4\n42\n5\n8\n8\n` と byte 単位で
  一致。同じ 12 構成の KIR compile と 8 正規化比較も成功。raw KIR は 7 比較で不一致が
  残り、すべて KUU-2140 の namespace 差で説明できた。artifact の body は直列 fallback。
  生 KIR から正規化結果と対応表も再生成して検証した。

## local 本体の参考測定

上記 benchmark の stdlib=none、各ファイル 4 関数、8 terms の initializer と 2 locals、
debug compiler。flag off/on × jobs=1/2/4 の各構成で warmup を除く 3 標本を採取した。
計測中に本作業の build/test/source-artifact gate は重ねていない。外部の host 負荷は
管理していないため、通常負荷や release の性能を示すものではない。
144 測定行を [生 TSV](sema-worker-ownership-measurements.tsv) に保存した。

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

全テスト、全 Golden、全 kotlinc diff、Linux / Swift 6.3、release compiler は未実行。
