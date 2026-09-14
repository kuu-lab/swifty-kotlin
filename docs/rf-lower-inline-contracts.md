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

全Swift・Golden・全Kotlin差分の結果はPRの検証欄に記録し、共通RFゲートが未完了ならTODOは `[~]` とする。
