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
| imported lambda ABI の erased invoke、primitive / nullable / erased generic の引数・戻り値の box / unbox | `InlineErasedLambdaABITests` と既存の `Inline` / imported-artifact 回帰。 |
| 展開内の無保護 call / virtualCall / rethrow が caller の catch へ届き、ローカル catch 済み・finally guard 内の経路を二重に書き換えない | `InlineThrowReroutingTests`（手組み KIR で reroute 後の命令列・dispatch label 採番・guard depth を固定）と `CodegenBackendInlineFunctionExceptionPropagationTests` / `FinallyExceptionRouteTests` / fixture `inline/captured_try_finally` の実行回帰。 |

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
`InlineTypeSubstitution.applying` へ委譲し、reified hidden-token の対応表は
`InlineReifiedTypeTokens` が所有する。`expandLambdaBody` 側の呼び出しは型代入を持たないため
`substituteType` の既定値（恒等関数）を使う。

抽出時に判明した既存の状態: `expandInlineCalls` の `aliases` は宣言時に空のまま一度も
書き込まれず、`InlineExprAliasing.definedResult` の結果を `removeValue` するだけで終わる
（展開結果は明示的な `.copy` で反映されるようになっており、alias登録の必要がなくなったため
と見られる）。したがって同スコープでの `InlineExprAliasing.rewriteInstruction` /
`resolveAlias` 呼び出しは現状すべて恒等写像になる。本PRは分離のみが目的で挙動を変えない
ため削除しない。除去を検討する場合は同ループの走査制御を扱うRF-LOWER-INLINE-009側で行う。

RF-LOWER-INLINE-005 以降、erased lambda / imported inline ABI の補正は
`Sources/CompilerCore/Lowering/InlineErasedLambdaABI.swift` の
`InlineErasedLambdaABI` が担う。`usesErasedLambdaABI`、erased function-value invoke の
callee 集合、primitive 引数の box / unbox、lambda の引数・戻り値および imported inline
結果の補正、浮動小数点演算前の erased invoke 結果の unbox をここへ移した。
これらのABI補正について `InlineLoweringPass` は展開順序・引数位置・nullable / erased generic
の判定を所有せず、このnamespaceを呼び出すだけにする。`ABILoweringPass` の実装と通常の ABI 規則は変更せず、
既存の imported lambda ABI 契約（erased slot は boxed、具体的な primitive slot は raw）を
維持する。

RF-LOWER-INLINE-006 以降、展開後の例外経路補正は
`Sources/CompilerCore/Lowering/InlineThrowRerouting.swift` の `InlineThrowRerouting` が担う。
状態を持たない namespace（`InlineExprAliasing` と同じ形）で、caller 側が持つ
`InlineLabelAllocator` へ `inout` で採番だけを委ねる。4つの責務を型・API で明示した:
caller の例外スロット（`callerThrownResult`、`nil` なら素通しで採番もしない）、
ローカル catch 済み命令（`thrownResult != nil` は再書き換えしない）、
finally guard 領域（`.beginFinallyGuard` / `.endFinallyGuard` の depth 内は素通し）、
dispatch label（戻り値 tuple の `throwDispatchLabel` -- caller 名前空間で
`callerThrownResult` 非 nil なら常に eager 採番し、呼び出し側が展開直後に
`.label` として emit して既存の throw-aware dispatch へ着地させる。NLR 用の
exit label とは別物で、同一 cursor 由来のため衝突しない）。
書き換え対象の命令分類（unprotected `.call` / `.virtualCall` / `.rethrow`）は
`callerRoute(for:thrownSlot:dispatchLabel:)` に集約し、`thrownResult == nil` だけを
判定根拠にして `canThrow` の意味や例外 ABI は変更しない。

RF-LOWER-INLINE-009 以降、展開対象の index と依存スケジューリングは分離
している。`Sources/CompilerCore/Lowering/InlineExpansionIndex.swift` の
`InlineExpansionIndex` が `SymbolID` 主キーのスナップショットと分類・
依存問い合わせを担う:

- `inlineFunctionsBySymbol` — 展開ターゲット（module `inline` 宣言 +
  imported inline 本体）。`.call` site でsplice対象になり得るのはこの表
  だけで、lambda 本体はここには入らない。
- `allFunctionsBySymbol` — module 宣言の全関数（通常 / inline /
  lambda 本体）。lambda 解決が使う lookup で、imported 本体は入らない。
- `origins` — 各展開ターゲットの出所（`.module` / `.imported`）。
- `bodylessInlineSymbols` — object ファイルに本体が残らない callee
  （module `isInlineOnly` + imported 全件）。ここへの呼び出しは必ず
  展開しなければならない。
- `originalBodies` — 凍結済みの展開前本体（両表の union、衝突時は
  module 宣言優先）。各ラウンドはこれを再展開し、二重展開しない。

依存情報は `bodylessCallees(of:)`（解決済み symbol の `.call` のみを辺
とし、名前のみの呼び出し・自己呼び出しは辺にしない）と
`pendingBodylessCallers(interner:)`（`snapshotExpansionOrder` — 名前・
パラメータ数・source range・symbol raw value の全順序 — で辞書列挙順
に依存しない処理順を返す）に抽出した。symbol 既知 call の束縛規則は
`inlineTarget(callSymbol:callee:inlineFunctionsByName:)` が持ち、既知
symbol は自身の snapshot にのみ束縛され同名 fallback へは流れない
（KSP-1011）。symbol 不明 call のみ一意な by-name 候補を使う。
`recordExpansion` が module 表・ターゲット表への書き戻しを一元化する。

スケジューリングは `InlineLoweringPass+Scheduling.swift` の
`expandNestedBodylessInlineCalls`（bodyless snapshot 4ラウンド、
`maxBodylessExpansionRounds`）と `inlineTransform`（caller 8ラウンド
再走査、`maxInlineExpansionRounds`）だけが担い、既存の回数制御は維持
する。ラウンド内で by-name 表を固定しつつ by-symbol 表は最新を参照する
逐次意味、pending が現在本体・展開が凍結 original を見る規則も不変。
固定回数の撤廃・循環検出・展開量制限は INLINE-010 以降の対象であり、
本PRでは変更しない。

全Swift・Golden・全Kotlin差分の結果はPRの検証欄に記録し、共通RFゲートが未完了ならTODOは `[~]` とする。
