# Stdlib source pipeline design

## 目的

KSwiftK の stdlib 実装は、合成スタブと Runtime `kk_*` 直接呼び出しから、`Sources/CompilerCore/Stdlib` 配下の Kotlin ソースを通常のフロントエンド入力として扱う形へ段階移行する。

この設計メモは RF-STDLIB-001 のレビュー対象であり、実装 PR の前に次の境界を固定する。

- bundled `.kt` の読み込み順序と source origin
- stdlib ソース宣言と合成スタブの優先順位
- インクリメンタルキャッシュと golden 出力への影響
- 常時 stdlib コンパイルの時間コストを抑える戦略

## 現状

`Package.swift` は `CompilerCore` の resource として `Sources/CompilerCore/Stdlib` をコピーしている。現 HEAD の `LoadSourcesPhase` は `Bundle.module.resourcePath/Stdlib` を列挙し、ソート済みの `.kt` を `SourceManager` に `__bundled_...` virtual path として登録してからユーザー入力を読む。未移行 API は `BundledKotlinStdlib` の residual source でも注入される。

このため、RF-STDLIB-002 の基本配線はすでに入り始めている。一方で、以下はまだ設計上の固定が必要。

- `--no-stdlib` / `-Xfrontend no-default-stdlib-sources` 相当の opt-out が bundled source 注入に効くか
- `SourceManager` 上でユーザー入力と bundled stdlib source を origin として区別できるか
- stdlib ソース宣言が存在する場合に同シグネチャの synthetic stub 登録を確実に skip できるか
- incremental build が bundled source の変更を fingerprint に含めるか
- golden と diagnostics が fileID 順序や virtual path に依存して揺れないか

## 読み込みフェーズ

### Source origin

`SourceManager` に origin を持たせる。

| origin | 例 | 用途 |
|---|---|---|
| `user` | CLI 入力の実パス | 通常診断、metadata export、golden の主対象 |
| `bundledStdlib` | `__bundled_kotlin/text/StringComparison.kt` | implicit stdlib source、metadata export から除外 |
| `residualStdlib` | `__bundled_kotlin_text_stdlib.kt` | 移行前 API の暫定 source、削除予定を追跡 |

既存の `__bundled_` prefix は、metadata export 除外やテストフィルタで使われているため維持する。ただし prefix 判定だけに依存せず、origin を source of truth にする。互換期間は `path.hasPrefix("__bundled_")` も残す。

### Load order

`LoadSourcesPhase` は次の順序で登録する。

1. bundled stdlib source を virtual path で登録する
2. residual stdlib source を virtual path で登録する
3. ユーザー入力を実パスで登録する

Bundled source は relative path で昇順ソートし、SwiftPM の resource 列挙順やファイルシステム順に依存しない。ユーザー入力は CLI 指定順を維持する。

この順序により fileID は安定する。golden では fileID の数値を期待値に直接出さず、source path と source position から安定キーを作る。

### Opt-out

stdlib source の opt-out は `CompilerOptions` に専用プロパティを追加して表現する。

- CLI alias: `-no-default-stdlib-sources`
- frontend flag: `-Xfrontend no-default-stdlib-sources`
- test helper: `includeDefaultStdlibSources: false`

既存の `--no-stdlib` / `includeStdlib` は search path や link-time stdlib の意味を持つため、bundled source の opt-out と混同しない。互換性のため `--no-stdlib` が bundled source も止めるかは別 PR で明示的に決める。

### 診断パス

ユーザー入力の読み込み失敗はこれまで通り `KSWIFTK-SOURCE-0002` と実パスを出す。bundled source の読み込み失敗は compiler packaging の問題なので、ユーザー入力とは別コードにする。

- `KSWIFTK-SOURCE-0101`: bundled stdlib resource directory is unavailable
- `KSWIFTK-SOURCE-0102`: bundled stdlib source could not be read

通常の parser / sema diagnostics は virtual path を表示してよいが、JSON/LSP では origin を含め、ユーザーが編集できない implicit file であることを区別できるようにする。

## 合成スタブとの優先順位

### 基本規則

Stdlib source 宣言を authoritative とする。

1. ユーザー宣言は通常の Kotlin 名前解決規則で扱う
2. bundled stdlib source 宣言があるシグネチャは synthetic stub を登録しない
3. residual stdlib source は bundled stdlib source と同じ優先度だが、削除予定として分類する
4. synthetic stub は stdlib source が未配線の API だけを補う

ここでいう「同シグネチャ」は少なくとも次を含む。

- package FQName
- declaration kind
- simple name
- receiver type
- value parameter arity and types
- type parameter arity
- return typeは警告メッセージに含めるが、skip 判定の主キーにはしない

### 登録フロー

`SemaPhase` の synthetic registration 前に、AST から stdlib source declaration index を作る。

```text
ASTModule
  -> StdlibSourceDeclarationIndex
  -> Synthetic registration guard
  -> SymbolTable
```

synthetic 登録ヘルパーは、登録前に index へ問い合わせる。

- 同シグネチャの stdlib source 宣言がある場合: stub 登録を skip
- 同名だがシグネチャが異なる場合: overload として登録可能
- 同シグネチャの stdlib source と synthetic stub が両方登録されそうな場合: warning を出して synthetic を skip

warning は移行 PR の監査用であり、通常ユーザーには出しすぎない。まず `-Xfrontend warn-stdlib-shadowed-stubs` のような開発用 flag で有効化し、RF-STDLIB-004 以降の縦切り PR で必要なら default warning 化する。

### 二重定義の扱い

二重定義は次のように分ける。

| 組み合わせ | 扱い |
|---|---|
| stdlib source vs synthetic stub | warning、synthetic を skip |
| bundled stdlib source vs residual stdlib source | warning、bundled source を優先 |
| user source vs bundled stdlib source | 通常の名前解決と重複診断。stdlib source を隠すための特殊扱いはしない |
| user source vs synthetic stub | 既存の shadowing 規則を維持し、必要な箇所だけ source 宣言化で解消 |

## インクリメンタルキャッシュ

### Fingerprint

incremental mode は user input だけでなく implicit stdlib source も入力集合に含める必要がある。

`IncrementalCompilationCache.computeCurrentFingerprints` には、次の logical input list を渡す。

1. ユーザー入力パス
2. bundled stdlib virtual path と content hash
3. residual stdlib virtual path と content hash
4. stdlib source manifest version

ファイルシステム実パスではなく virtual path + contents で fingerprint する。SwiftPM resource の展開先が build directory ごとに変わっても cache key が揺れないようにする。

### Build configuration hash

`IncrementalBuildConfiguration` には次を追加する。

- stdlib source manifest hash
- include default stdlib sources flag
- residual stdlib source version

`time-phases` や `jobs=N` と同じく出力非影響 flag は除外するが、stdlib source opt-out は出力に影響するので hash に含める。

### Frontend state reuse

stdlib source は多くのユーザー入力から参照される。stdlib source fingerprint が変わった場合、dependency graph が完全でない期間は full frontend rebuild に落とす。依存関係が symbol-level に十分記録できるようになった後で、stdlib source に依存するユーザーファイルだけを再解析する。

RF-STDLIB-006 の pre-parse cache は、既存の `IncrementalFrontendState` を拡張して次を分けて保存する。

- stdlib-only interner snapshot
- stdlib AST snapshot
- stdlib symbol seed

初期実装では AST snapshot までを目標にし、Sema symbol seed は synthetic registration skip が安定してから検討する。

## Golden と diff ハーネス

### FileID と出力順

Golden は fileID 数値を期待値にしない。表示順が必要な場合は次の sort key を使う。

1. source origin: user, bundled stdlib, residual stdlib
2. normalized path
3. source offset
4. declaration stable key

通常の user-facing golden は user origin を主対象にし、stdlib 宣言は「参照された required symbol」だけを表示する。stdlib pipeline 自体の golden では bundled origin を明示的に含める。

### 診断ソート

diagnostics は source location sort の前に origin と path を安定化する。virtual path は `/private/...` の resource 展開先を含めない。`__bundled_` path をそのまま使う。

### diff_kotlinc.sh

`Scripts/diff_kotlinc.sh` は implicit stdlib source 込みを default とする。stdlib source pipeline を切り分ける regression では、kswiftc 側だけ `-Xfrontend no-default-stdlib-sources` を使えるようにして、synthetic fallback との差分を見られるようにする。

## コンパイル時間戦略

### 計測

RF-STDLIB-006 では `-Xfrontend time-phases` で次を比較する。

- bundled stdlib source なし
- bundled stdlib source あり
- bundled + residual source あり

最低限 `LoadSources`, `Lex`, `Parse`, `BuildAST`, `SemaPasses` の増分を記録する。必要なら `PhaseTimer.recordSubPhase` で `LoadBundledStdlib` と `ParseBundledStdlib` を分ける。

### 許容ライン

常時 stdlib source による overhead は、Smoke 相当の小さい入力で次を目安にする。

- wall-clock 15% 未満、または 200 ms 未満
- golden suite で 10% 未満
- `diff_kotlinc.sh` shards で 10% 未満

これを超える場合は pre-parse cache を導入する。

### Pre-parse cache

pre-parse cache の key は以下。

- compiler version or frontend schema version
- stdlib source manifest hash
- parser/AST schema version
- output-affecting frontend flags

保存対象は段階導入する。

1. lex/parse 結果
2. AST snapshot
3. source declaration index
4. sema seed

最初から sema seed まで入れると synthetic registration skip と type interning の不変条件が重くなるため、RF-STDLIB-006 では 1 または 2 までを候補にする。

## E2E 縦切りテンプレート

RF-STDLIB-004 以降の各移行 PR は、同じチェックリストで進める。

1. 対象 API を `Sources/CompilerCore/Stdlib` の `.kt` へ置く
2. bundled source として `LoadSourcesPhase` から読まれることを確認する
3. 同シグネチャ synthetic stub が skip されることをテストする
4. TypeCheck fallback を削除する
5. KIR/CallLowerer の direct `kk_*` dispatch を source-backed symbol 経由へ変える
6. Runtime `@_cdecl` を削除するか、`kswiftk.internal.__*` bridge に降格する
7. RuntimeABISpec と ABI parity テストを更新する
8. golden と `diff_kotlinc.sh` を更新する

`StringComparison.kt` の `commonPrefixWith` / `commonSuffixWith` を最初の縦切りにする。次に `StringSplitJoin.kt` を移行し、`kk_string_split*` 直接 dispatch を Kotlin 層経由に置換する。

## 完了条件

RF2 の完了条件は次の通り。

- bundled stdlib source が default でコンパイルに含まれる
- opt-out がテストから使える
- SourceManager が source origin を保持する
- stdlib source 宣言が synthetic stub より優先される
- duplicated source/stub surface を warning で検出できる
- incremental cache が implicit stdlib source を fingerprint と build hash に含める
- golden と diagnostics が deterministic に並ぶ
- compile-time overhead が PhaseTimer で記録され、閾値超過時の cache 方針が実装される
