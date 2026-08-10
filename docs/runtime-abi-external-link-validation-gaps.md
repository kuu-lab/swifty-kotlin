# Runtime ABI external link validation gaps

`RuntimeABIExternalLinkValidationTests` が目指す不変条件は、CompilerCore が実行時 ABI 呼び出しとして emit しうる `kk_*` 名が `RuntimeABISpec` に宣言されていること。
RF-KIR-005 で enforcing 化する前提として、現行テストの検証範囲と未検証の経路を棚卸しする。

## 現行テストの範囲

`Tests/CompilerCoreTests/Sema/RuntimeABIExternalLinkValidationTests.swift` は次の 2 系統を確認している。

1. `fun noop() {}` を Sema まで通し、登録済み symbol の `externalLinkName` を `RuntimeABISpec.allFunctions` に照合する。
2. `Sources/CompilerCore/{KIR,Lowering,Sema}` を走査し、限られた正規表現で拾った `kk_*` literal を `RuntimeABISpec.allFunctions` に照合する。

2 の collector が拾う形は以下だけ。

```swift
interner.intern("kk_example")
externalLinkName == "kk_example"
someName: "kk_example"
```

## 調査時の実測

再現に使ったコマンド:

```bash
bash Scripts/dead_code_audit.sh --output-dir /tmp/swifty-kk-audit-rf-guard-004 --verbose
```

主な数値:

| 項目 | 件数 |
|---|---:|
| Runtime `@_cdecl("kk_*")` 宣言 | 2726 |
| CompilerCore 静的 `kk_*` 参照 | 2559 |
| CompilerCore 動的補間 prefix | 23 |
| `StdlibSurfaceSpec` 表駆動 link name | 164 |
| CompilerCore 到達可能総数（静的 + 動的 prefix 展開 + 表駆動） | 2605 |

現行 collector と同じ対象ルートだけを別途比較すると、`Sources/CompilerCore/{KIR,Lowering,Sema}` の raw `kk_*` token 2548 個に対し、collector が拾うのは 2153 個だった。差分 395 個はコメントや prefix 断片も含むため、そのまま missing ABI 名ではないが、現行 collector の検出モデルが完全ではないことを示す。

`CompilerCore` 全体の raw `kk_*` token のうち、`RuntimeABISpec` 登録名または現行 allowlist に完全一致しないものは 68 個だった。主な内訳は動的 prefix、CompilerCore 内部 symbol 名、prefix 判定用の断片であり、未宣言 ABI 名の確定リストではない。

## 検証ギャップ一覧

### 1. Sema 側は空ソース 1 ケースに依存している

`testRegisteredSemaExternalLinkNamesExistInRuntimeABI` は `fun noop() {}` だけを通した後の symbol table を見ている。全 synthetic stub がこの最小コンテキストで常に登録されるなら十分だが、次の経路はテスト上の明示的な証明がない。

- import やライブラリ metadata import によって初めて現れる `externalLinkName`
- source shape に依存する synthetic symbol
- future の stdlib source pipeline で、登録タイミングが conditional になる symbol

RF-KIR-005 で enforcing するなら、「空ソースで全 synthetic external link が登録済み」という前提をテスト名または helper で明示するか、複数コンテキストを fixture 化する必要がある。

### 2. 正規表現 collector が `kk_*` literal の一般形を拾わない

現行 collector は `interner.intern("...")`、`== "..."` / `!= "..."`、`*Name: "..."` に限定される。以下は raw scan では見えるが、現行 collector では一般的には拾えない。

- array / set / dictionary literal 内の `kk_*` 名
- `hasPrefix("kk_*")` / `hasSuffix("...")` 用の prefix 断片
- local variable 代入の prefix 断片（例: `let lambdaPrefix = "kk_lambda_"`）
- `symbols.setExternalLinkName("kk_*", for: ...)` のような第1引数 literal（Sema の空ソース登録で拾われる前提に依存）

これらを全部 raw token として enforcement すると false positive が多いので、「ABI link 名」「compiler-internal `kk_*` symbol」「prefix 断片」を分類した collector が必要。

### 3. 動的補間で生成される完全名を展開していない

CompilerCore には `"kk_xxx_\(value)"` 形式の dynamic emit がある。現行 collector は完全名として抽出できない。

代表例:

- `LambdaClosureConversionPass.swift`: `kk_closure_obj_\(lambdaSymbolRaw)`、`kk_closure_invoke_\(lambdaSymbolRaw)`

`dead_code_audit.sh` は prefix を集め、Runtime `@_cdecl` 名に前方一致させるモデルを持っている。RF-KIR-005 の enforcement では、この prefix 展開を `RuntimeABISpec` 側にも適用する必要がある。

### 4. `StdlibSurfaceSpec` 表駆動 link name が別モジュール側にある

Collection HOF の一部は CompilerCore の literal ではなく、`RuntimeABI` の `StdlibSurfaceSpec.collectionHOFMembers` から `runtimeLinkName` として渡される。

代表例:

- `CollectionLiteralLoweringPass+LookupTables.swift` が `spec.runtimeLinkName` を `interner.intern` する
- `MemberRuntimeDispatch.collectionRuntimeLinkName` が `StdlibSurfaceSpec` を経由する

現行 `RuntimeABIExternalLinkValidationTests` は `Sources/CompilerCore` だけを literal scan するため、`StdlibSurfaceSpec.collectionHOFMembers.map(\.runtimeLinkName)` が `RuntimeABISpec.allFunctions` に含まれることを直接検証していない。

### 5. CompilerCore 内部 `kk_*` 名前空間と ABI 名が混在している

raw scan では次のような CompilerCore 内部名や prefix が ABI 候補に見える。

```text
kk_lambda_
kk_closure_obj_
kk_closure_invoke_
kk_object_literal_
kk_type_register_
kk_launcher_thunk_
```

これらは Runtime ABI 関数ではないものを含むため、単純な `kk_*` 全件照合はできない。enforcing 化では allowlist を「なぜ RuntimeABISpec 対象外か」で分類し、意図しない追加をレビューしやすくする必要がある。

### 6. allowlist の意味づけが弱い

現行の `allowedCompilerExternalLinks` は `kk_for_lowered`、`kk_program_main`、一部 operator variant、`kk_unknown_callable` などをまとめて除外している。内部 intrinsic、legacy lowered name、RuntimeABI 未登録の意図的例外が同じ集合に入っているため、今後の追加が本当に安全か判断しにくい。

RF-KIR-005 では、少なくとも次の分類に分けるとよい。

- compiler-internal synthetic callee
- lowered helper name that never links to Runtime
- dynamic prefix marker, not a complete ABI symbol
- temporary legacy exception with removal task

## RF-KIR-005 への引き継ぎ

enforcing 化で必要な検証単位:

1. 登録済み Sema `externalLinkName` は `RuntimeABISpec.allFunctions` に含まれる。
2. CompilerCore が literal として直接 emit する ABI link 名は `RuntimeABISpec.allFunctions` に含まれる。
3. CompilerCore の dynamic prefix は、展開可能な Runtime/RuntimeABISpec 名集合に前方一致させ、対象外 prefix は理由付き allowlist に置く。
4. `StdlibSurfaceSpec.collectionHOFMembers.map(\.runtimeLinkName)` は `RuntimeABISpec.allFunctions` に含まれる。
5. compiler-internal `kk_*` namespace は ABI link 名とは別分類にし、raw scan の false positive として明示的に除外する。
