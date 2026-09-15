# RF-LOWER-INLINE-001: 抽出前の契約と検証先

後続の Inline 分割では、以下の既存テストと追加した小さな回帰テストを使う。
展開回数・循環・展開量の制限変更は RF-LOWER-INLINE-010 以降で扱う。

| 契約 | 検証先 |
|---|---|
| 同名でも解決済みの非 inline symbol を展開しない | `LoweringPassRegressionTests+InlineContracts.swift` の `testInlineLoweringPreservesResolvedNonInlineOverload`。Kotlin ソースから2 overloadを解決して比較する。 |
| nested inline、既存ラベルとの衝突回避、同一入力の決定性 | 同ファイルの `testNestedInlineLabelRelocationIsDeterministicAndCollisionFree`。2段の展開を2箇所で呼び、ラベル一意性・jump参照・独立した2回のKIR生成結果を確認する。 |
| call の symbol・型・throw channel・qualified super、virtual call の receiver・dispatch | 同ファイルの `testInlineExpansionPreservesVirtualAndQualifiedSuperMetadata`。通常関数とラムダ展開の2経路で確認する。 |
| 実ソースの `super<Left>` の型指定 | 同ファイルの `testSourceInlinePreservesQualifiedSuperTarget` と Backend fixture `inline/qualified_super`。KIRの型指定と出力の両方を確認する。 |
| imported inline とライブラリ内getterへの参照 | `LibraryMetadataImportIntegrationTests` の `testInlineLoweringExpandsImportedInlineFunctionFromKklib` / `testImportedInlineBodyCallsLibraryPropertyGetterByLinkName`。 |
| imported virtual call の受理 | `LibMetadataImportIntegrationTests.testInlineKIRArtifactWithVirtualCallIsImported`。 |
| 捕捉lambda、nested inline、try/catch/finally の実行 | Backend fixture `inline/captured_try_finally`。捕捉値を返す経路と例外経路でfinallyの実行を確認する。`inline/qualified_super` は捕捉したthisでの呼び出しも実行する。 |
| lambdaの展開・解決不能時のfallback・const alias | `LoweringPassRegressionTests+InlineLambdaInlining.swift`。解決できないclosureを無理に展開しない契約も含む。 |
| reified token と型代入 | `LoweringPassRegressionTests+InlineReifiedTypeToken.swift`、`CodegenBackendInlineFunctionExceptionPropagationTests.swift`、`Scripts/diff_cases/inline_reified.kt`。 |
| non-local return と通常returnの混在 | `LoweringPassRegressionTests+InlineNonLocalReturn.swift`、`Scripts/diff_cases/bug_209_inline_nonlocal_return.kt`。 |
| catch内の複数call、inline castから呼び出し元catchへの例外伝播 | `CodegenBackendInlineFunctionTryCatchValueReturnTests.swift` / `+InlineFunctionExceptionPropagation.swift`。 |
| stdlib artifact経由の展開 | `StdlibArtifactRegressionTests` の `testInlineOnlyCallInsideSplicedLambdaThroughSharedStdlibArtifact` など既存suite。 |
| ラベル採番と再配置の規則（caller基準・4種のラベル保持命令すべて） | `InlineLabelAllocatorTests`。`allocateCallerLabel` / `allocateScratchLabel` の基準値と `relocate` の並び保存を確認する。 |
| 展開経路をまたいだラベルの一意性 | `LoweringPassRegressionTests+InlineContracts.swift` の `testDirectLambdaInvokeAndInlineCallDoNotReuseLabelIDs`。caller本体に残った `kk_function_invoke` の展開と通常inline展開が同じ採番状態を使うことを固定する。 |
| alias解決の循環・自己参照・チェーンの終端規則 | `InlineExprAliasingTests` の `testResolveAlias*` 4件。 |
| `rewriteInstruction` が call/virtualCallのsymbol・throw channel・dispatch・superを変更せず引数のみ解決する | 同ファイルの `testRewriteInstruction*` 3件。 |
| `definedResult` が `.copy` の書き込み先を定義とみなさない | 同ファイルの `testDefinedResultIgnoresACopysDestination`。 |
| `cloneOrReuseExpr` の初回複製・メモ化再利用・型置換クロージャの委譲・欠落sourceのfallback | `InlineExprCloningTests` 5件。 |
| generic / nullable / function receiver / nested type argument の置換と reified token の hidden argument 対応 | `InlineTypeSubstitutionTests` の substitution 生成・適用と token map の回帰、既存 `LoweringPassRegressionTests+InlineReifiedTypeToken.swift` および imported-inline integration。 |

INLINE-001 の修正は、`expandInlineCall` / `expandLambdaBody` が `.call` を複製するときに落としていた `qualifiedSuperType` を引き継ぐもの。
最小ソースは実行結果だけでは欠落を検出できないため、展開前後のKIRにもassertionを置いている。
Backend fixtureはstdout・終了状態の回帰を受け持ち、KIR検証の代わりにはしない。

Coreの追加テストは `Tests/CompilerCoreTests/Lowering/`、上記Backend integrationファイルは
`Tests/CompilerBackendTests/Codegen/`、importテストは各targetの `Sema/` にある。
実行fixtureは `Tests/CompilerBackendTests/Fixtures/` 以下で自動検出される。

RF-LOWER-INLINE-002 以降、inline展開が導入するラベルIDは `InlineLabelAllocator`
（`Sources/CompilerCore/Lowering/InlineLabelAllocator.swift`）が所有する。採番は二空間
あり、組み立て中の展開に渡す scratch ID は `relocate(_:)` が必ず振り直すため出力には
現れない。caller本体へ着地するIDを一つのカーソルに集めていることが衝突不可能性の根拠
なので、`relocate(_:)` を通さずに展開を append してはならない。

RF-LOWER-INLINE-003 以降、alias解決・命令operand書換え・式複製は `InlineExprAliasing`
（`Sources/CompilerCore/Lowering/InlineExprAliasing.swift`）と `InlineExprCloning`
（`Sources/CompilerCore/Lowering/InlineExprCloning.swift`）が担う。どちらも状態を持たない
namespace（`KIRLabelRelocation` と同じ形）で、`expandInlineCalls` / `expandInlineCall` /
`expandLambdaBody` 側が持つ alias map（`aliases` / `localExprMap`）は呼び出し側の所有のまま
`inout` で渡す -- パラメータ代入やmerge-slot昇格などalias解決ではない書き込みも同じ
mapに対して行われるため、mapの所有権自体は移していない。型置換は
`InlineExprCloning.cloneOrReuseExpr`/`cloneExpr` の `substituteType` クロージャ経由で
`InlineTypeSubstitution.substituteInlineType` へ委譲する。`expandLambdaBody` 側の呼び出しは
型代入を持たないため `substituteType` の既定値（恒等関数）を使う。

抽出時に判明した既存の状態: `expandInlineCalls` の `aliases` は宣言時に空のまま一度も
書き込まれず、`InlineExprAliasing.definedResult` の結果を `removeValue` するだけで終わる
（展開結果は明示的な `.copy` で反映されるようになっており、alias登録の必要がなくなったため
と見られる）。したがって同スコープでの `InlineExprAliasing.rewriteInstruction` /
`resolveAlias` 呼び出しは現状すべて恒等写像になる。本PRは分離のみが目的で挙動を変えない
ため削除しない。除去を検討する場合は同ループの走査制御を扱うRF-LOWER-INLINE-009側で行う。

RF-LOWER-INLINE-004 以降、型引数の収集・再帰的な置換・reified token の hidden argument
対応は `Sources/CompilerCore/Lowering/InlineTypeSubstitution.swift` の
`InlineTypeSubstitution` が担う。`buildInlineTypeSubstitution` は inline target の
parameter/argument 型から mapping を作り、実際の再帰置換は既存の
`TypeSystem.substituteTypeParameters` へ委譲する。`buildTypeParamTokenValues` は同じ
target signature の reified index と `SyntheticSymbolScheme` を使って token symbol を
型パラメータ symbol へ対応付ける。通常 inline と imported inline の両方が同じ helper
を経由し、nullable wrapper・generic type argument・function receiver の情報を落とさない。

全Swift・Golden・全Kotlin差分の結果はPRの検証欄に記録し、共通RFゲートが未完了ならTODOは `[~]` とする。
