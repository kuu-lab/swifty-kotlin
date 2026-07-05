# ARCHITECTURE.md

> **Purpose**: AI 向け認知ナビゲーションガイド。「このタスクではどこを触ればよいか」を素早く判断するための地図。

---

## 1. プロジェクト概要

**KSwiftK** は Swift で書かれた Kotlin コンパイラ。Kotlin 2.3.10 stable をターゲットとし、LLVM 経由で macOS ネイティブ実行ファイルを生成する。

| 属性 | 値 |
|---|---|
| 言語 | Swift 6.2 (Swift language mode 6) / macOS 12+ |
| ビルドシステム | SwiftPM (`Package.swift`) |
| 実行バイナリ | `kswiftc` |
| テストフレームワーク | XCTest + Swift Testing |
| CI | GitHub Actions (`.github/workflows/ci.yml`) |

---

## 2. モジュール構成

```text
Package.swift
 +-- CLLVM                (system)      LLVM C API ブリッジ (modulemap)
 +-- RuntimeABI           (target)      Runtime ABI 契約と extern view の共有境界
 +-- CompilerCore         (library)     フロントエンド (Lex〜Lowering)、LLVM 非依存
 +-- CompilerBackend      (library)     バックエンド (Codegen + Link)、LLVM 依存
 +-- KSwiftKCLI           (executable)  CLI エントリポイント -> kswiftc
 +-- LSPServer            (library)     Language Server Protocol 実装
 +-- KSwiftLSPCLI         (executable)  LSP サーバ CLI エントリポイント -> kswift-lsp
 +-- GoldenHarnessSupport (library)     ゴールデンテスト共通ハーネス
 +-- GoldenHarnessWorker  (executable)  ゴールデンテスト実行ワーカー
 +-- Runtime              (library)     GC / coroutine / boxing ヘルパー
```

### 依存グラフ

```text
KSwiftKCLI           --> CompilerBackend --> CLLVM, CompilerCore, RuntimeABI
                         CompilerCore    --> RuntimeABI
KSwiftLSPCLI         --> LSPServer       --> CompilerCore
GoldenHarnessWorker  --> GoldenHarnessSupport --> CompilerCore
CompilerCoreTests    --> CompilerCore, GoldenHarnessSupport, GoldenHarnessWorker
CompilerBackendTests --> CompilerBackend, CompilerCore
RuntimeTests         --> RuntimeABI
RuntimeTestsParallel --> RuntimeABI
LSPServerTests       --> LSPServer, CompilerCore
Runtime (独立 — リンク時に結合)
```

---

## 3. コンパイルパイプライン (心臓部)

`CompilerDriver.run()` が以下の Phase を順に実行する。  
各 Phase は `CompilerPhase` プロトコルに準拠し、`CompilationContext` を読み書きする。

```text
LoadSources --> Lex --> Parse --> BuildAST --> SemaPasses --> BuildKIR --> Lowering --> Codegen --> Link
```

| # | Phase | 入力 | 出力 (ctx に格納) | 主要ファイル |
|---|-------|------|-------------------|-------------|
| 1 | **LoadSources** | ファイルパス | `sourceManager` にファイル登録 | `Driver/FrontendPhases.swift` |
| 2 | **Lex** | ソースバイト列 | `ctx.tokens`, `ctx.tokensByFile` | `Driver/FrontendPhases.swift`, `Lexer/KotlinLexer*.swift` |
| 3 | **Parse** | トークン列 | `ctx.syntaxTrees` (CST) | `Driver/FrontendPhases.swift`, `Parser/KotlinParser*.swift` |
| 4 | **BuildAST** | CST | `ctx.ast` (ASTModule) | `Driver/FrontendPhases.swift`, `AST/BuildASTPhase+*.swift` |
| 5 | **SemaPasses** | AST | `ctx.sema` (SemaModule) | `Sema/Infrastructure/SemaPhase.swift` -> `DataFlow/Phase.swift` + `TypeCheck/TypeCheckSemaPhase.swift` |
| 6 | **BuildKIR** | AST + Sema | `ctx.kir` (KIRModule) | `KIR/BuildKIRPhase.swift`, `KIR/KIRLoweringDriver.swift` |
| 7 | **Lowering** | KIR | KIR (in-place 変換) | `Lowering/LoweringPhase.swift` + 各 `*LoweringPass.swift` |
| 8 | **Codegen** | KIR | `.o` / `.ll` / `.kir` / `.kklib` | `Codegen/CodegenPhase.swift`, `Codegen/LLVMBackend.swift`, `Codegen/NativeEmitter.swift` |
| 9 | **Link** | `.o` ファイル | 実行ファイル (clang 呼び出し) | `Codegen/LinkPhase.swift` |

---

## 4. ディレクトリマップ — 「どこを触るか」早見表

### `Sources/CompilerCore/` (コンパイラ本体)

| ディレクトリ | 責務 | 主要型/ファイル | 典型タスク |
|---|---|---|---|
| `Lexer/` | トークン化 | `KotlinLexer.swift`, `KotlinLexer+Strings.swift`, `KotlinLexer+Literals.swift`, `TokenModel.swift`, `TokenStream.swift` | 新リテラル追加、文字列テンプレート修正 |
| `Parser/` | CST 構築 | `KotlinParser.swift`, `KotlinParser+Declarations.swift`, `KotlinParser+Statements.swift`, `SyntaxArena.swift` | 新構文のパース対応 |
| `AST/` | CST -> AST 変換 | `BuildASTPhase+*.swift` (20+ファイル), `ASTModels.swift`, `ASTDeclModels.swift`, `ASTExprModels.swift`, `ASTArena.swift` | 新 AST ノード追加、式パーサ修正 |
| `Sema/` | 型チェック / データフロー解析 | `Infrastructure/SemaPhase.swift`, `DataFlow/Phase.swift`, `TypeCheck/TypeCheckSemaPhase.swift`, `Resolution/OverloadResolver.swift`, `Resolution/ConstraintSolver.swift`, `TypeSystem/TypeSystem.swift`, `Models/SemanticsModels.swift`, `TypeSystem/TypeModels.swift` | 型推論修正、オーバーロード解決、smart cast |
| `KIR/` | 型付き中間表現 | `KIRModels.swift`, `BuildKIRPhase.swift`, `KIRLoweringDriver.swift` (+ ModuleLowering / ObjectInitializer / ProvideDelegate 分割), `KIRLoweringContext.swift`, `KIRLoweringContextTypes.swift`, `ExprLowerer.swift` (+ CallsAndTypeOps / ControlFlowAndBlocks / ControlFlowHelpers / InstructionLocationTracking 分割), `CallLowerer.swift` (+ member / stdlib / coroutine / type-of などの分割), `CallSupportLowerer.swift` (+ DefaultArgsAndVarargs), `ControlFlowLowerer.swift` (+ FlowEntryPoints / ThrowCatchAndWhen / WhenExpr), `MemberLowerer.swift` (+ DelegatedAndAccessorLowering), `LambdaLowerer.swift` (+ CaptureAnalysis / CallableResolutionAndCapture / ClosureEntryPoints), `ObjectLiteralLowerer.swift` (+ ObjectLiteralEntryPoints), `KIRCallEmissionHelpers.swift`, `ConstantCollector.swift`, `LateinitReadWrapping.swift`, `KClassAnnotationRegistrationLowering.swift`, `MutableCaptureCellHelpers.swift`, `RuntimeTypeCheckToken.swift` | IR 命令追加、コール生成修正 |
| `Lowering/` | KIR 脱糖パス群 | `LoweringPhase.swift` (パス登録), 各パス: `TailrecLoweringPass`, `NormalizeBlocksPass`, `OperatorLoweringPass`, `ForLoweringPass`, `CollectionLiteralLoweringPass`, `FlowLoweringPass`, `ValueClassUnboxingPass`, `PropertyLoweringPass`, `StdlibDelegateLoweringPass`, `JvmStaticLoweringPass`, `JvmOverloadsLoweringPass`, `DataEnumSealedSynthesisPass`, `EnumEntriesLoweringPass`, `EnumNameAccessLoweringPass`, `LambdaClosureConversionPass`, `InlineLoweringPass`, `CoroutineLoweringPass` (+Analysis / +CallRewriting / +Flow / +FlowInstructionRewrite / +LauncherSupport / +StateMachine / +Synthesis; 計8ファイル), `IntegerNarrowingPass`, `ABILoweringPass` | for/when/property のデシュガー修正、新 lowering pass 追加 |
| `Sema/NameMangler.swift` | マングリング | `NameMangler` | シンボル名マングリング修正 |
| `Driver/` | パイプライン制御 + 横断インフラ | `Driver.swift`, `CompilationContext.swift`, `Diagnostics.swift`, `Phases.swift`, `FrontendPhases.swift`, `SourceManager.swift`, `SourceLocation.swift`, `CommandRunner.swift`, `PhaseTimer.swift`, `IncrementalCompilationCache.swift`, `DependencyGraph.swift`, `FileFingerprint.swift` | 新フェーズ追加、診断メッセージ修正、インクリメンタルビルド |
| `Stdlib/` | Kotlin stdlib ソース（リソース） | `kotlin/collections/*.kt`, `kotlin/text/*.kt` 等 | stdlib 拡張関数の追加・修正 |

### `Sources/CompilerBackend/` (LLVM バックエンド)

| ファイル | 責務 |
|---|---|
| `BackendPhaseProvider.swift` | `makeBackendPhases()` — CodegenPhase + LinkPhase を提供 |
| `CodegenPhase.swift` | KIR → LLVM IR 変換フェーズ |
| `LinkPhase.swift` | オブジェクト → 実行ファイルリンクフェーズ |
| `LLVMBackend.swift` | LLVM バックエンドエントリ |
| `LLVMCAPIBindings.swift` (+分割4ファイル) | LLVM C API の Swift ラッパー |
| `NativeEmitter.swift` (+分割4ファイル) | ネイティブコード発行 |
| `CodegenRuntimeSupport.swift` | ランタイムサポート関数 |
| `CodegenSymbolSupport.swift` | シンボルサポート |

### `Sources/KSwiftKCLI/`

| ファイル | 責務 |
|---|---|
| `main.swift` | CLI 引数パース、`CompilerDriver` 呼び出し |

### `Sources/LSPServer/`

| ファイル | 責務 |
|---|---|
| `Server.swift` | LSP サーバメインループ、JSON-RPC ディスパッチ |
| `Analyzer.swift` | ソース解析、診断結果の LSP 変換 |
| `DocumentStore.swift` | 開いているドキュメントの状態管理 |
| `PositionResolver.swift` | ソース位置 ↔ LSP Position 変換 |
| `JSONRPC.swift` | JSON-RPC プロトコル実装 |
| `LSPTypes.swift` | LSP 型定義 |
| `Conversions.swift` | コンパイラ内部型 ↔ LSP 型の変換 |

### `Sources/KSwiftLSPCLI/`

| ファイル | 責務 |
|---|---|
| `main.swift` | LSP サーバ CLI エントリポイント |

### `Sources/Runtime/` (83 ファイル — カテゴリ別抜粋)

| カテゴリ | 主要ファイル | 責務 |
|---|---|---|
| 型・メモリ | `RuntimeTypes.swift`, `RuntimeBoxing.swift`, `RuntimeGC.swift`, `RuntimeMemory.swift`, `RuntimeMetadata.swift` | `KTypeInfo`, ヒープ管理、mark-sweep GC、ボックス型 |
| 文字列 | `RuntimeStringArray.swift`, `RuntimeStringBuilder.swift`, `RuntimeStringSearch.swift`, `RuntimeStringHOF.swift` 等 (12 ファイル) | 文字列操作・検索・変換・フォーマット |
| コレクション | `RuntimeCollections.swift`, `RuntimeCollectionHOF.swift`, `RuntimeCollectionHelpers.swift`, `RuntimeArrayBasics.swift`, `RuntimeSetAndMap.swift` 等 | 配列・リスト・セット・マップ操作 |
| Coroutine/Flow | `RuntimeCoroutine.swift`, `RuntimeCoroutineChannel.swift`, `RuntimeCoroutineContext.swift`, `RuntimeCoroutineFlow.swift` | coroutine ステートマシン、Channel、Flow |
| 数値・演算 | `RuntimeMath.swift`, `RuntimeNumericCoercion.swift`, `RuntimeNumericBitManip.swift`, `RuntimeRandom.swift` | 数値変換・ビット操作・乱数 |
| IO・ネットワーク | `RuntimeFileIO.swift`, `RuntimeNetwork.swift`, `RuntimePath.swift`, `RuntimeURI.swift` | ファイル IO、HTTP、パス操作 |
| プラットフォーム | `RuntimeHelpers.swift`, `RuntimePlatform.swift`, `RuntimeSystem.swift`, `RuntimeTime.swift`, `RuntimeInstant.swift` | ヘルパー関数、プラットフォーム検出、時間 |
| Delegate | `RuntimeDelegates.swift` | delegate プロパティランタイムサポート |
| 並行・同期 | `RuntimeAtomic.swift`, `RuntimeSync.swift`, `RuntimeThread.swift`, `RuntimeParallel.swift` | アトミック操作、ロック、スレッド |

### `Sources/RuntimeABI/`

| ファイル | 責務 |
|---|---|
| `RuntimeABISpec.swift` | Runtime ABI 仕様定数と C ヘッダ生成 |
| `RuntimeABIExterns.swift` | `RuntimeABISpec` から導出される extern 宣言 view |

### `Sources/CLLVM/`

| ファイル | 責務 |
|---|---|
| `include/llvm_shim.h` | LLVM C API ヘッダブリッジ |
| `module.modulemap` | SwiftPM 用モジュールマップ |

---

## 4.1 ファイル分割命名規約

- 分割ファイルの suffix は責務ベースで命名する（例: `+MemberCallResolution.swift`, `+TypeAliasExpansion.swift`）。
- `+Part`, `+Part2`, `+Part3` のような番号付き分割名は新規追加しない。
- この規約は `Sources` と `Tests` の両方に適用する。
- 分割ファイルの責務が変わった場合は、同一 PR でファイル名も更新する。

---

## 5. テスト構造

```text
Tests/
 +-- CompilerCoreTests/         # フロントエンドテスト (LLVM 不要)
 |    +-- Lexer/          # TokenModelTests, TokenStreamTests, LexerParserEdgeCaseTests
 |    +-- Parser/         # SyntaxArenaTests
 |    +-- AST/            # ASTModelsTests, BuildASTBodyParsingRegressionTests, BlockExpressionTests
 |    +-- Sema/           # ConstraintSolverTests, OverloadResolverTests, TypeSystemTests, ...
 |    +-- KIR/            # BuildKIRRegressionTests, KIRModelsBehaviorTests, ...
 |    +-- Lowering/       # LoweringPassRegressionTests, VirtualDispatchTests, ...
 |    +-- Driver/         # DriverTests, DiagnosticEngineTests, SourceLocationTests, ...
 |    +-- Integration/    # SmokeTests, GoldenHarnessSwiftTesting, DeepPhasePipelineIntegrationTests
 |    +-- GoldenCases/    # .kt スナップショットフィクスチャ (Lexer/, Parser/, Sema/)
 +-- CompilerBackendTests/     # バックエンドテスト (LLVM 必要)
 |    +-- Codegen/        # CodegenBackendIntegrationTests, LinkPhaseIntegrationTests, NameManglerTests
 |    +-- Lowering/       # LoweringCodegenRegressionTests, VirtualDispatchCodegenTests, ...
 |    +-- Sema/           # LibraryMetadataImportIntegrationTests
 |    +-- KIR/            # BuildKIRCodegenRegressionTests, DelegatePropertyKIRTests
 +-- RuntimeTests/            # ランタイムユニットテスト
 +-- RuntimeTestsParallel/    # ランタイム並列テスト
 +-- KSwiftKCLITests/         # CLI 統合テスト
 +-- LSPServerTests/          # LSP サーバテスト
```

### テスト実行コマンド

```bash
bash Scripts/swift_test.sh                               # 全テスト (並列)
bash Scripts/swift_test.sh --filter SmokeTests           # スモークテスト
bash Scripts/swift_test.sh --filter Golden   # ゴールデンテスト（Swift Testing）
UPDATE_GOLDEN=1 bash Scripts/swift_test.sh --filter matchesGolden  # フィクスチャ更新
bash Scripts/diff_kotlinc.sh Scripts/diff_cases           # kotlinc 差分回帰テスト
```

---

## 6. データフロー — 中間表現の流れ

```text
ソースコード (.kt)
    |
    v
[Token]                      -- TokenKind + SourceRange + Trivia
    |
    v
SyntaxArena (CST)            -- NodeID/TokenID ベース、ロスレス
    |
    v
ASTModule                    -- ASTArena (DeclID/ExprID/TypeRefID)
  +-- ASTFile[]                 各ファイルの package/imports/decls
    |
    v
SemaModule                   -- SymbolTable + TypeSystem + BindingTable
  +-- SymbolTable               SymbolID -> SemanticSymbol (FQName, FunctionSignature, NominalLayout)
  +-- TypeSystem                TypeID -> TypeKind (primitive/class/function/typeParam/intersection)
    |
    v
KIRModule                   -- KIRArena (KIRDeclID/KIRExprID)
  +-- KIRFunction[]             KIRInstruction 列 (レジスタベース SSA 風)
  +-- KIRGlobal[]
  +-- KIRNominalType[]
    |
    v  (Lowering passes: in-place 変換)
KIRModule (lowered)
    |
    v
.o (LLVM object) or .ll (LLVM IR) or .kir (dump) or .kklib (library bundle)
    |
    v  (Link: clang 呼び出し)
実行ファイル
```

---

## 7. 重要な設計原則

| 原則 | 詳細 |
|---|---|
| **ID ベース** | すべてのシンボル/型/ノード参照は整数 ID (`SymbolID`, `TypeID`, `NodeID` 等)。文字列比較は行わない |
| **インターン** | 識別子・名前は `StringInterner` で `InternedString` (Int32) に変換。`CompilationContext.interner` 経由 |
| **決定性** | 同一入力 + 同一オプション = ビット同一出力 (HashMap iteration 順に依存しない) |
| **エラー耐性** | どんな入力でもクラッシュしない。`fatalError` は ICE (`KSWIFTK-ICE-xxxx`) のみ |
| **診断コード** | すべてのエラー/警告に `KSWIFTK-*` プレフィックスコードを付与 |
| **フェーズ分離** | 各 `CompilerPhase` は `CompilationContext` のみを介してデータを受け渡す |

---

## 8. 横断インフラストラクチャ

| コンポーネント | 場所 | 役割 |
|---|---|---|
| `CompilationContext` | `Driver/CompilationContext.swift` | 全フェーズの共有状態コンテナ (tokens, AST, Sema, KIR, options) |
| `DiagnosticEngine` | `Driver/Diagnostics.swift` | エラー/警告の収集・ソート・表示 (`KSWIFTK-*` コード体系) |
| `SourceManager` | `Driver/SourceManager.swift` | ファイル管理、行列番号計算 (O(log N)) |
| `StringInterner` | `Driver/CompilationContext.swift` 内 | 文字列 -> InternedString (Int32) の双方向変換 |
| `SymbolTable` | `Sema/Models/SemanticsModels.swift` | シンボル定義・FQName/ShortName 索引・関数シグネチャ・レイアウト |
| `TypeSystem` | `Sema/TypeSystem/TypeSystem.swift` | 型の登録・部分型判定・変性・置換 |
| `NameMangler` | `Codegen/NameMangler.swift` | ABI 安定なマングル名生成 |
| `PhaseTimer` | `Driver/PhaseTimer.swift` | フェーズ実行時間計測 (`-Xfrontend time-phases`) |
| `IncrementalCompilationCache` | `Driver/IncrementalCompilationCache.swift` | 入力フィンガープリント + build 構成 hash による no-op output artifact 再利用、および file-level frontend state (interner + AST) の復元 |

---

## 9. Codegen バックエンド

LLVM C API を `dlopen`/`dlsym` で動的ロードし、ネイティブ IR を生成する単一バックエンド:

| クラス | 説明 |
|---|---|
| `LLVMBackend` | LLVM C API 動的ロード。`NativeEmitter` が KIR → LLVM IR 変換を実行 |

---

## 10. Lowering パス実行順序

`Sources/CompilerCore/Lowering/LoweringPhase.swift` の `passes` 配列で定義。順序に依存関係あり:

```text
1.  TailrecLoweringPass          -- tailrec 関数のループ変換 (beginBlock に依存、NormalizeBlocks 前に実行)
2.  NormalizeBlocksPass          -- ブロック正規化
3.  OperatorLoweringPass         -- 演算子展開
4.  ForLoweringPass              -- for ループ脱糖 (iterator パターン)
5.  CollectionLiteralLoweringPass -- コレクションリテラル展開
6.  FlowLoweringPass             -- Kotlin Flow 構築・変換
7.  ValueClassUnboxingPass       -- value class のアンボクシング (PropertyLowering 前に実行)
8.  PropertyLoweringPass         -- get/set アクセサ展開
9.  StdlibDelegateLoweringPass   -- lazy/observable/vetoable delegate
10. JvmStaticLoweringPass        -- @JvmStatic アノテーション処理
11. JvmOverloadsLoweringPass     -- @JvmOverloads デフォルト引数オーバーロード生成
12. DataEnumSealedSynthesisPass  -- data/enum/sealed synthetic ヘルパー
13. EnumEntriesLoweringPass      -- enum entries プロパティ合成
14. EnumNameAccessLoweringPass   -- enum name アクセスの展開
15. LambdaClosureConversionPass  -- ラムダクロージャ変換
16. InlineLoweringPass           -- inline 関数本体展開
17. CoroutineLoweringPass        -- suspend 関数 CPS 変換 + ステートマシン
18. IntegerNarrowingPass         -- 整数型ナローイング最適化
19. ABILoweringPass              -- outThrown チャネル設定
```

---

## 11. CI ジョブ構成

`.github/workflows/ci.yml` の主なジョブ:

| ジョブ | 内容 |
|---|---|
| `jscpd-check` | コード重複検出 (閾値 5%) |
| `smoke-tests` | `SmokeTests` フィルタでスモークテスト実行（`SWIFT_TEST_PARALLEL=0` で順序安定） |
| `full-swift-tests` | `CompilerCoreTests` / `CompilerBackendTests` / `RuntimeTests` 等をマトリクスで全テスト実行 |
| `diff-regression-shards` | `Scripts/diff_kotlinc.sh` で kotlinc との出力一致検証（シャード分割で並列実行。失敗時は TSV と `.artifacts` 相当を Artifact に保存、`DIFF_LOG_PASS=0` で PASS 行省略） |
| `diff-regression` | 全シャードの結果を集約して成否判定 |

セットアップアクション:
- [`.github/actions/setup-swift`](../.github/actions/setup-swift/action.yml) — Swift のみ（LLVM 不要なジョブ用）
- [`.github/actions/setup-swift-llvm`](../.github/actions/setup-swift-llvm/action.yml) — Swift + LLVM（バックエンド・diff テスト用）

LLVM 不要: `CompilerCoreTests`, `RuntimeTests`, `RuntimeTestsParallel`, `LSPServerTests`
LLVM 必要: `build`, `smoke-tests`, `CompilerBackendTests`, `KSwiftKCLITests`, `diff-regression`

### CI 失敗時のデバッグ（短い手順）

- **kotlinc diff が落ちた場合**: ジョブの **Summary**（`kotlinc Diff Regression Summary`）と **Artifacts**（`kotlinc-diff-regression-<run id>`）を確認。全文ログでは `FAIL ` で検索。`gh run view <id> --log-failed` だけでは、`continue-on-error` により diff 本体のステップが「失敗扱い」にならず **差分ログが出ない**ことがある。
- **スモーク**: Summary にローカル再現用コマンドを記載。`jscpd` 失敗時も Summary に再現コマンドを追記。

---

## 12. タスク別ナビゲーション — どこを見るか

### 新しい Kotlin 構文をサポートする

1. `Lexer/` — 新トークンが必要なら `TokenModel.swift` の `TokenKind` / `Keyword` を拡張
2. `Parser/` — `KotlinParser+Declarations.swift` or `KotlinParser+Statements.swift` にパースルール追加
3. `AST/` — `ASTDeclModels.swift` or `ASTExprModels.swift` に新 AST ノード追加、`BuildASTPhase+*.swift` で CST->AST 変換
4. `Sema/` — `DataFlow/Phase.swift` でヘッダ収集、`TypeCheck/TypeCheckSemaPhase.swift` で型チェック
5. `KIR/` — `ExprLowerer.swift` or `MemberLowerer.swift` で KIR 生成
6. `Lowering/` — 必要なら専用 `*LoweringPass.swift` を追加し `LoweringPhase.passes` に登録
7. テスト — `Tests/CompilerCoreTests/` の該当ディレクトリ + `Scripts/diff_cases/` に回帰ケース追加

### 型チェック / 型推論のバグを直す

1. `Sema/TypeCheck/TypeCheckSemaPhase.swift` — 式型チェックのメインドライバ
2. `Sema/TypeCheck/ExprTypeChecker.swift` — 式ごとの型推論ロジック
3. `Sema/TypeCheck/CallTypeChecker.swift` — 関数呼び出しの型チェック
4. `Sema/Resolution/OverloadResolver.swift` — オーバーロード候補のランキング
5. `Sema/Resolution/ConstraintSolver.swift` — ジェネリクス型引数推論
6. `Sema/TypeSystem/TypeSystem.swift` — 部分型判定 (`isSubtype`)、`TypeSystem/Subtyping.swift`, `TypeSystem/Substitution.swift`

### コード生成 / リンクエラーを直す

1. `Codegen/LLVMBackend.swift` — LLVM バックエンド初期化・エラーハンドリング
2. `Codegen/NativeEmitter.swift` + `NativeEmitter+FunctionEmission.swift` — KIR → LLVM IR エミッション
3. `Codegen/CodegenPhase.swift` — Codegen フェーズ制御、emit モード分岐
4. `Codegen/LinkPhase.swift` — リンクコマンド構築、エントリラッパー生成
5. `Codegen/NameMangler.swift` — シンボル名マングリング
6. `RuntimeABI/RuntimeABIExterns.swift` — ランタイム ABI extern view

### ランタイム動作のバグを直す

1. `Sources/Runtime/` 配下の該当ファイル
2. `RuntimeHelpers.swift` — `kk_println_any` 等の出力系
3. `RuntimeGC.swift` — GC 関連
4. `RuntimeCoroutine.swift` — coroutine ステートマシン

### 診断メッセージを追加 / 修正する

1. `Driver/Diagnostics.swift` — `DiagnosticEngine` の API
2. 各フェーズ内で `ctx.diagnostics.error(...)` / `.warning(...)` を呼ぶ
3. コード体系: `KSWIFTK-{PHASE}-{NUMBER}` (例: `KSWIFTK-PARSE-0001`, `KSWIFTK-SEMA-0001`)

### テストを追加する

| テスト種別 | 場所 | 実行方法 |
|---|---|---|
| フェーズ単体テスト | `Tests/CompilerCoreTests/{Phase}/` | `bash Scripts/swift_test.sh --filter {TestClass}` |
| ゴールデンテスト | `Tests/CompilerCoreTests/GoldenCases/` | `bash Scripts/swift_test.sh --filter Golden` |
| kotlinc 回帰テスト | `Scripts/diff_cases/*.kt` | `bash Scripts/diff_kotlinc.sh Scripts/diff_cases` |
| E2E スモークテスト | `Tests/CompilerCoreTests/Integration/SmokeTests.swift` | `bash Scripts/swift_test.sh --filter SmokeTests` |

---

## 13. 主要な型 ID 一覧

コードベース全体で使われる ID 型。すべて `Int32` ベース、無効値は `-1`。

| ID 型 | 定義場所 | 用途 |
|---|---|---|
| `FileID` | `Driver/SourceManager.swift` | ソースファイル識別 |
| `InternedString` | `Driver/CompilationContext.swift` | インターン済み文字列 |
| `NodeID` | `Parser/SyntaxArena.swift` | CST ノード |
| `TokenID` | `Parser/SyntaxArena.swift` | CST トークン |
| `DeclID` | `AST/ASTArena.swift` | AST 宣言 |
| `ExprID` | `AST/ASTModels.swift` | AST 式 |
| `TypeRefID` | `AST/ASTModels.swift` | AST 型参照 |
| `SymbolID` | `Sema/Models/SemanticsModels.swift` | 意味解析シンボル |
| `TypeID` | `Sema/TypeSystem/TypeModels.swift` | 型システム内の型 |
| `KIRDeclID` | `KIR/KIRModels.swift` | KIR 宣言 |
| `KIRExprID` | `KIR/KIRModels.swift` | KIR 式/レジスタ |

---

## 14. ライブラリ配布形式 (.kklib)

`--emit library` で生成される `.kklib` バンドルの構造:

```text
module.kklib/
  manifest.json        -- formatVersion, moduleName, target, objects[], metadata, inlineKIRDir
  metadata.bin         -- シンボル/型/レイアウト情報のシリアライズ
  objects/
    module_0.o         -- コンパイル済みオブジェクト
  inline-kir/
    *.kirbin           -- inline 関数の KIR シリアライズ (跨モジュール inline 展開用)
```

消費側: `-I path/to/module.kklib` でインポート。`Sema/DataFlow/LibraryImport.swift` 系ファイルで読み込み。

---

## 15. 並列処理

フロントエンドフェーズ (Lex, Parse, BuildAST) はファイル単位で並列実行可能:

- `-Xfrontend jobs=N` で並列度を指定
- `Swift.TaskGroup` を使用、`DispatchSemaphore` で同期
- 並列実行後は `FileID` 順でソートし決定性を保証
- 診断メッセージも `sortBySourceLocation()` でソース位置順に安定化
