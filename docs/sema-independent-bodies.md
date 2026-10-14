# Sema の独立な本体区間の実験（KUU-2000）

2026-10-13。段階 1 の [監査](sema-parallelization.md) に続く、限定的な初期実装。
汎用の per-file type-check 並列化の完了ではない。性能改善が確認できていないため、
既定の経路は直列のまま、実験には `-Xfrontend sema-parallel -Xfrontend jobs=N` を使う。

## 分離した区間

追記（2026-10-14）: [worker 所有権の続き](sema-worker-ownership.md) で通常 scalar local
の block 本体を対象へ追加した。以下の限定文法・測定・検証は #8864 時点の記録である。
lambda/object は独立 snapshot の所有権を検証し、本番 join は引き続き直列とする。

ヘッダ準備は、凍結済み AST から宣言値と未解決 TypeRefID を保持する
`UnresolvedHeader` を作り、alias とその他の宣言に分ける。worker は SymbolTable、
型解決、合成登録、scope insert、bundled 登録の thread-local context に触れない。
nominal の先行登録、nested nominal、Number/Unit、alias、その他の登録は既存順序の
直列バリアを維持する。ヘッダの型解決自体は並列化していない。

本体では、明示戻り型と非 nullable の primitive/String 引数を持つ、独立な式本体を
対象にする。literal、引数参照、単項式、一部の二項式、if の閉じた文法に限る。
receiver/context receiver、generic、default/vararg 引数、inline/suspend、annotation、
呼び出し、local 宣言、lambda、object literal は対象外。

各ファイルは ASTArena、SymbolTable、TypeSystem、StringInterner の COW snapshot、
新しい BindingTable、DiagnosticEngine、driver/delegate、solver/resolver/cache を所有する。
共有 file/import scope は join まで凍結する。scalar 演算子も source extension を
検索するため、空の scope には置き換えない。

worker が新しい SymbolID、診断、exprTypes/identifierSymbols 以外の binding side table
を生成したら、ファイル結果を捨て module driver で直列再検査する。Worker.execute、
call/capture/return 等の副表もこの拒否条件に含める。lazy metadata loader がある module
では本体 worker を開始しない。loader closure をコピーして module の型や inline store
を書き換えることを防ぐためであり、artifact 経路の成功を並列化成功とは数えない。

contract 先行収集、constructor initializer、inferred property 固定点反復は worker 開始前に
完了する。inferred return/property と deferred/checking/checked 帳簿、診断 rollback、
signature 復元は module driver に残す。worker は未確定宣言の推論を demand できない。

`SemaPerFileExecutor` は最大 jobs 個の 64 MiB stack worker を起動し、失敗時も全 task を
join して input 順に結果/最初の error を返す。本体の採用結果は元の file/decl 位置で
マージする。型検索用の一時型も含め、追加 TypeKind を宣言順に canonicalize し、
binding の worker TypeID を書き換える。中間の直列宣言が型を追加しても prefix と
新規型の対応を保つ。PhaseTimer は親 thread のみが更新する。

深い式の検証で、既存 ComparableCharEscapeAnalyzer が薄い caller stack 上で再帰し
stack guard に到達する問題を発見した。型検査後のこの走査も joined large-stack thread
で行い、binding の最終更新は親に戻す。80 項の Kotlin 式を回帰テストに含めた。

## 計測

専用 [benchmark](../Scripts/benchmark_sema_independent.py) は既存 KUU-1999 の計測基盤を
変更せず、同じ compiler の flag off/on、jobs=1/2/4 を比較する。各構成の warmup 後に
3 標本を保持し、構成順を交互に反転する。RSS は wait4 で各 compiler process の
最大値を取得する。Sema 単独の RSS ではない。

```bash
python3 Scripts/benchmark_sema_independent.py --files 10 50 100 \
  --functions 4 --terms 8 --jobs 1 2 4 --runs 3 > /tmp/sema-independent.tsv
```

Swift 6.4、arm64、debug compiler、stdlib=none。1 ファイル 4 関数、各本体は
8 個の `x * x` を加算する。親の SwiftPM build/test と source/artifact gate は
計測中に実行していない。外部の host 負荷は管理していない。
この表は ASTArena snapshot 導入後・ComparableChar post-pass の stack 修正前の
参考測定で、後者の変更後の再測定ではない。
全標本は [TSV](sema-independent-body-measurements.tsv) に保存した。

| files | jobs | flag | Sema 中央値 ms | type-check 中央値 ms | process 最大 RSS 中央値 MiB |
| --- | --- | --- | ---: | ---: | ---: |
| 10 | 4 | off | 50.29 | 6.54 | 25.84 |
| 10 | 4 | on | 58.64 | 10.46 | 27.17 |
| 50 | 4 | off | 100.45 | 33.37 | 39.12 |
| 50 | 4 | on | 101.52 | 41.57 | 45.08 |
| 100 | 4 | off | 163.37 | 52.95 | 57.38 |
| 100 | 4 | on | 173.93 | 66.07 | 75.16 |

この条件では snapshot/準備/join の追加コストを回収できず、RSS も増える。
通常コードや release compiler の高速化を示すデータではなく、既定有効化の根拠にも
使わない。一般的な呼び出しや local/lambda/object の SymbolID/副表 delta、lazy loader
分離、依存推論の並列実行、snapshot の worker 単位再利用は残作業である。

## 検証範囲

jobs=1/2/4 の反復比較は診断全内容/順序、source position ごとの raw TypeID/SymbolID/callee
を確認する。inferred 宣言、local 本体、operator extension、nested typealias、型の
canonical join、抑制/rollback/件数上限、worker 上限/stack/失敗時 join を含める。
通常実行と Thread Sanitizer は各 12 tests / 2 suites、parameter 展開後 18 cases が成功。
80 項の式は修正前に通常・TSAN とも ComparableCharEscapeAnalyzer の stack guard で
落ちることを確認し、修正後は両方で成功した。TSAN の競合診断はない。
既存の ComparableChar local escape codegen テスト 1 件も期待 stdout と一致した。

現 compiler で新規 stdlib artifact を生成し、source 注入 / fresh artifact の
O0/O2 × jobs=1/2/4 全 12 executable compile/run が成功、全 stdout は
`37\n4\n42\n` と byte 単位で一致した。同じ 12 構成の KIR compile も成功し、
各経路・最適化で jobs=1 対 jobs=2/4 の全 8 比較が一致した。
正規化は tmp path と行末空白のみで、ID は除去していない。
fixture は square、別ファイルの明示型関数、inferred return 関数、main の 2 ファイル。
artifact の本体は lazy loader による直列 fallback の検証である。

初回 executable link は、コンパイラ内の SwiftPM sandbox に親 tool sandbox が重なり
`sandbox_apply: Operation not permitted` で失敗した。親 tool の正規 escalation で
コンパイラ自身の sandbox を保持して runtime cache を生成した後、全構成を再実行した。
runtime manifest の捏造や SwiftPM sandbox を外すコード変更は行っていない。

全テスト、全 Golden、全 kotlinc diff はこの実装のローカル gate に含めない。
一般的な本体を並列化したという結論、コア数に比例する高速化、KUU-2000 全項目の
完了は主張しない。
