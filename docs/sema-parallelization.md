# Sema per-file 並列化の検討（KUU-1965）

調査日: 2026-10-13。基準: master
`a1ad746b646afab1ccb242033740e0c6528979e0`。

PR 作成時に master `e1293decea93c909662dc1483b6e0bb69d6ca87a` へ追従し、
tailrec 検証の TypeCheck 後処理への移動と inferred return の on-demand 処理を
再監査した。以下の処理区間・共有状態は追従後の実装を記述する。
参考測定の生データは元の基準 HEAD で採取したもので、追従後の再測定値ではない。
公開前の最終追従先は `5e1dbf6ffadfb0beb79f22b420197ceda44a0c34`。

## 判断と今回の範囲

現行の `collectAllHeaders` / `typeCheckModule` をそのまま並列ループに
置き換えることはできない。共有テーブルの同期と意味的な依存関係を先に
分離する必要がある。今回の成果物は段階 1 の競合点監査、Sema の区間計測、
多数ユーザーファイル用の再実行可能なベンチマークである。
`frontendJobs` の Sema への適用（段階 2）は実装していない。

Lex/Parse は既存の per-file 並列処理、BuildAST は `jobs=N` を使う。
今回も Sema 全体は直列であるため、jobs=1/4 の計測差を Sema の並列化による
高速化と解釈してはいけない。KUU-1960 の stdlib artifact 経路拡大とは独立に、
主な評価対象は多数ファイルのユーザーコードとする。

## 実際のパスと依存関係

| 区間 | 処理と依存 | 並列化候補 |
| --- | --- | --- |
| DataFlow の準備 | bundled index、package/file scope、import、early nominal、synthetic 登録 | 読み取り専用の AST 走査を、登録用の記述子生成から分離する |
| `collectAllHeaders` | bundled 優先・FileID 順に nominal を先行登録し、nested nominal、Number/Unit、typealias、残りの宣言の順で確定する | シンボル登録前の AST 走査・未解決型の記述子生成のみ。登録・解決は各バリアの後に同じ順序で行う |
| `runValidationPasses` | 継承、override、expect/actual、annotation の検証に加え、delegation forwarding、既定引数、nominal layout、metadata を更新する | 純粋な検証と合成・更新を分け、確定済み snapshot を使う検証だけを評価する |
| `runBodyAnalysis` / `analyzeBody` | top-level 関数の重複引数名を検査する。SymbolTable/TypeSystem/BindingTable の引数は使わない | 読み取り専用 AST とローカル診断収集なら per-file で独立。ただし主要な型推論ではない |
| `TypeCheckDriver.typeCheckModule` | contract と inferred return 関数の先行登録、constructor initializer の型確定、inferred property の固定点反復、宣言順本体検査と inferred return の on-demand 推論 | 先行パスを全ファイルで完了後、依存が確定した関数本体を限定して評価する。現状は共有書き込みと別関数の on-demand 推論が残る |
| TypeCheck の後処理 | const 評価、JS file annotation、tailrec/return/suspension 検証、ComparableChar escape 解析 | 本体の結果をマージした後に実行する |

根拠:
[DataFlow/Phase.swift](../Sources/CompilerCore/Sema/DataFlow/Phase.swift)、
[BodyAnalysis.swift](../Sources/CompilerCore/Sema/DataFlow/BodyAnalysis.swift)、
[TypeCheckDriver.swift](../Sources/CompilerCore/Sema/TypeCheck/TypeCheckDriver.swift)、
[ForwardReferenceInference.swift](../Sources/CompilerCore/Sema/TypeCheck/DeclTypeChecker+ForwardReferenceInference.swift)、
[InferredFunctionReturns.swift](../Sources/CompilerCore/Sema/TypeCheck/TypeCheckDriver+InferredFunctionReturns.swift)、
[TypeCheckSemaPhase.swift](../Sources/CompilerCore/Sema/TypeCheck/TypeCheckSemaPhase.swift)。

## 共有状態の監査

チケットの「SymbolTable/TypeSystem/BindingTable は lock 保護」という記述は
この HEAD の実装と一致しない。ロックの存在を、テーブル全体の並列安全性の
根拠にしてはいけない。

| 状態 | 現行の保護と競合点 | 必要な契約 |
| --- | --- | --- |
| SymbolTable | `define` と `ensureLazyImportedMetadataLoaded` 等は NSRecursiveLock を使用するが、`symbol` / `allSymbols` / `setFunctionSignature` / `setPropertyType` 等はそのロックを取らない | 全アクセスを含む同期方針と、宣言・local/lambda/object literal の決定的な採番。`define` だけをロックしても読み書き競合と順序依存は残る |
| TypeSystem | `kindToID` / `idToKind` と nominal metadata はロックなし。`make` は検索と採番・追加を行う | worker-local 型と canonical TypeID へのマージ、または全読み書きの同期。ID と overload 順序の決定性は別途保証する |
| BindingTable | 辞書・集合の読み書きにロックなし。異なる ExprID への書き込みでも同じ Swift Dictionary を変更する | worker-local delta と読み取り snapshot。decl/type/call/capture/return 等の全 side table を対象にする |
| Scope | `BaseScope.locals` / `insert` / `insertWithAlias` にロックなし。親 scope を lookup chain で共有する | 共有 scope はバリア後に読み取り専用にし、local scope は worker 所有にする。ヘッダ準備 worker は既存 scope へ insert しない |
| StringInterner | intern/resolve はロック保護されるが、新規 InternedString の採番は到着順 | 合成名の ID 順序が結果に影響する箇所を監査し、必要なら記述子とともに順序付きで登録する |
| TypeCheckDriver | lazy delegate、`precheckedPropertyDecls`、`callSuspensionContexts`、inferred return 関数の登録・checking/checked 状態を共有。SemaCacheContext も可変キャッシュを持つ | worker ごとの driver・delegate・resolver/cache。先行パスの prechecked 集合を渡し、suspension context は post-pass 用にマージする。inferred return の重複推論・循環検出を module 全体で維持する。driver を分けるだけでは共有 Sema テーブルは安全にならない |
| lazy imported metadata | SymbolTable の recursive lock 内の callback が TypeSystem や imported inline store も更新しうる。読み取り API からロードが起きる | ロード前確定 snapshot、または loader が触る全状態を含む同期。symbol/type の lock 順序を固定して再入・逆順取得を監査する |
| DiagnosticEngine | emit はロック保護されるが、内部の保存順は到着順（render は source location でソート）。推測的推論の checkpoint/rollback は共有配列の末尾を扱う | worker-local 診断と推測トランザクション。join 後に file/decl 順で emit し、抑制・重複除去・件数上限を保持する |
| bundled 登録 context | `BundledSyntheticStubRegistration` は `Thread.current.threadDictionary` を使用する | ヘッダ worker に暗黙に継承されない。明示的 context の受け渡しが必要 |
| AST / 実行 stack | ASTArena はロックを持つが、worker で新規 ID を作ると採番順は変わりうる。型推論は 64 MiB stack の LargeStackExecutor を使用する | ID の扱いを決め、再帰的処理の worker にも large stack を確保する。DispatchQueue の既定 stack に移さない |
| PhaseTimer | `currentSubRecords` はロックなし | 親 thread が dispatch/join を囲んで壁時計時間を記録する。worker から書き込まない |

根拠:
[SymbolTable](../Sources/CompilerCore/Sema/Models/SemanticsModels+SymbolTable.swift)、
[TypeSystem](../Sources/CompilerCore/Sema/TypeSystem/TypeSystem.swift)、
[BindingTable](../Sources/CompilerCore/Sema/Models/SemanticsModels+BindingTable.swift)、
[Scope](../Sources/CompilerCore/Sema/Models/SemanticsModels+Scopes.swift)、
[StringInterner](../Sources/CompilerCore/Lexer/TokenModel.swift)、
[LocalDeclTypeChecker](../Sources/CompilerCore/Sema/TypeCheck/LocalDeclTypeChecker.swift)、
[SemaCacheContext](../Sources/CompilerCore/Sema/Infrastructure/SemaCacheContext.swift)、
[DiagnosticEngine](../Sources/CompilerCore/Driver/Diagnostics.swift)、
[bundled context](../Sources/CompilerCore/Sema/DataFlow/BundledDeclarationIndex.swift)、
[LargeStackExecutor](../Sources/CompilerCore/Driver/LargeStackExecutor.swift)。

## 計測の再実行

`-Xfrontend time-phases` は Sema の中に次の非重複区間を記録する。

* `sema-setup`: DataFlow の準備（bundled index、scope/import、early nominal/synthetic 登録、imported metadata の正規化）。
* `header-collection`: `collectAllHeaders` のみ。early nominal/synthetic 登録は含まない。
* `declaration-validation`: `runValidationPasses`（合成・metadata 更新も含む）。
* `body-checks`: `runBodyAnalysis`（重複引数名）。元の測定 HEAD では tailrec も含んでいた。
* `type-check`: large-stack thread の起動・join、本体型推論、const 評価、JS file annotation 検証。

残差 `Sema - 上記 5 区間の合計` には各区間外の patch、TypeCheck の scope 構築や
tailrec/return/suspension/escape 検証等が含まれる。
計測を有効にしないコンパイルでは追加の時計読み取りは行わない。
表示は既存の PhaseTimer と同じ 0.01 ms 単位であり、短い区間の評価には限界がある。

```bash
swift build
python3 Scripts/benchmark_sema.py --files 10 50 100 --jobs 1 4 --runs 3 > /tmp/sema-user.tsv
python3 Scripts/benchmark_sema.py --stdlib source --files 1 --jobs 1 4 --runs 3 > /tmp/sema-source.tsv
# Artifact は同じコンパイラで生成した互換な .kklib を明示する。
python3 Scripts/benchmark_sema.py --stdlib artifact --stdlib-library /path/to/stdlib.kklib \
  --files 10 50 100 --jobs 1 4 --runs 3 > /tmp/sema-artifact.tsv
```

スクリプトはビルド済みコンパイラを使い、各構成の初回を warmup として除外し、
jobs 構成をラウンドごとに交互に実行する。TSV は全標本を保持する。
コンパイル失敗・timeout・計測項目不足は失敗として扱う。
`none` は stdlib 注入を無効化し、共有 package の class/interface と、別ファイルの
inferred property を参照する明示戻り型の関数を測る。synthetic bootstrap は残る。
`source` / `artifact` は別条件であり、これらの結果を混ぜて集計しない。
KIR 出力まで実行するが、TSV に報告するのは Sema の時間だけである。
KIR/Lowering、プロセス起動、Lex/Parse/BuildAST の時間は含めない。

## 初回の参考測定

2026-10-13、Swift 6.4、arm64、debug ビルド。ユーザーコード条件は
各構成 1 回の warmup 後に 3 標本を採取した。測定時のホスト load average
（1 分値）は約 380〜486 で、他の Swift コンパイルも多数実行されていた。
このため通常負荷での絶対性能、スケーリング、高速化率の評価には使えない。
ユーザーコード条件の計測中は自分のビルドとベンチマークを重ねていない。
ソース注入条件の確認中には、長時間化したため対象テストのビルドを開始した。
ソース注入条件も参考確認に限定する。

以下は各区間の中央値（ms）。Sema の最小〜最大値も併記する。
区間ごとの中央値の合計は Sema の中央値と一致するとは限らない。
全標本は [sema-parallelization-measurements.tsv](sema-parallelization-measurements.tsv)
に保存した（同じ列形式の user/source 出力を結合）。

| user files（stdlib=none） | jobs | Sema | Sema 最小〜最大 | body-checks | type-check |
| --- | --- | ---: | --- | ---: | ---: |
| 10 | 1 | 643.21 | 559.97〜1395.91 | 0.03 | 103.22 |
| 10 | 4 | 685.88 | 441.17〜968.80 | 0.03 | 171.64 |
| 50 | 1 | 2293.93 | 1796.42〜2328.58 | 0.11 | 537.50 |
| 50 | 4 | 2287.63 | 2282.80〜2318.22 | 0.11 | 80.50 |
| 100 | 1 | 5907.09 | 4850.14〜7165.58 | 0.21 | 1023.28 |
| 100 | 4 | 7133.53 | 4201.08〜7317.62 | 0.57 | 1315.75 |

ソース注入条件は 636 stdlib + 1 ユーザーファイル、jobs=1、warmup 後の
**1 標本**のみを採取した。対象テストのビルドも並行しており、中央値や通常負荷の
基準値として扱わない。

| 区間 | 参考値（ms） |
| --- | ---: |
| Sema 全体 | 206346.23 |
| sema-setup | 564.94 |
| header-collection | 7827.04 |
| declaration-validation | 5641.27 |
| body-checks | 3.80 |
| type-check | 185180.47 |

この fixture では独立な `body-checks` の寄与が小さい。header の登録前段だけで
どこまで改善できるかは、その処理を分離してから計測する必要がある。
ソース注入条件でも主要区間は `type-check` であり、`runBodyAnalysis` を
並列にするだけではチケットの期待効果に届かない。
jobs 間の差は既に直列の Sema の揺れであり、並列化の効果ではない。
artifact 条件・release ビルド・通常負荷での測定は今回未実行である。

## 実装に進む条件と分割

1. **header 準備の分離**: 読み取り専用 AST から未解決記述子を作る API を設計し、
   nominal / nested nominal / alias / その他の既存バリアを保持する。
   合成登録と型解決を同じ worker に入れない。分離後にその区間のコストを測る。
2. **型・symbol・binding の所有権**: 本体を worker-local snapshot/delta で実行できる
   契約を確定し、local/lambda/object literal の採番、inferred signature、全 binding
   side table と lazy metadata の扱いを独立に検証する。
3. **依存バリア**: contract 先行収集・inferred property 固定点反復を保持する。
   inferred return と循環依存は依存解析なしに独立と判定しない。明示戻り型でも
   body の local 宣言と共有型生成は残るため、それだけを安全性の条件にしない。
4. **runner**: 上記契約が成立した区間だけに `frontendJobs` を適用する。
   `LockedIndexedResults` と同じ indexed result を利用し、jobs 上限を守り、
   file/decl 順でマージする。recursive work の large stack と失敗時の join を保証する。
5. **意味・性能の検証**: jobs=1/2/4 と反復実行で、診断の全内容・順序、型、callee、
   SymbolID/TypeID の扱い、正規化した KIR を比較する。前方参照・nested typealias・
   contract・inferred property/return・local/object literal・lazy import・抑制/rollback・
   深いラムダを含める。source と fresh artifact、対象の O0/O2 実行、利用可能なら
   Thread Sanitizer も確認する。ユーザーコードの中央値とメモリを測り、改善を確認して
   から対象区間を有効にする。

各項目は別の変更として検証する。共有 Sema を大きなロックで囲んだまま per-file
task を起動しても実行は直列になり、期待するコア数比例の高速化は得られない。
純粋な `body-checks` だけの並列化で主要な型推論の高速化を代替してはいけない。

## 今回の検証範囲

* `swift build --disable-sandbox`: 全製品のビルドを確認。
  最終追従後は `swift build --disable-sandbox --product kswiftc -j 2` も終了コード 0。
* 次の対象テストはビルドを伴って再実行し、終了コード 0、13 tests / 2 suites が成功した。
  正常入力の式型とエラー入力の診断の一致、jobs=1/4、区間の境界、throw 時の記録を確認した。
  既存の合計時間テストは時計の分解能に依存する非ゼロ判定を除き、記録数、
  合計値、ミリ秒への単位変換を検証する形に修正した。

  ```bash
  SWIFT_TEST_PRODUCT=CompilerCoreTests SWIFT_TEST_BUILD_JOBS=2 \
    /opt/homebrew/bin/bash Scripts/swift_test.sh --disable-sandbox --no-parallel \
    --filter 'SemaPhaseTimingTests|PhaseTimerTests'
  ```

* ベンチマークの user/source 条件はコンパイル成功と全計測項目を確認。
  最終スクリプトの 1 ファイル smoke、引数拒否、Python 構文、TSV の標本・列数、
  `git diff --check` も確認した。

全テスト・全 Golden・全 kotlinc diff、artifact 条件、release、O0/O2 の実行比較、
Thread Sanitizer は未実行。今回は並列処理や生成コードの変更を導入していない。
