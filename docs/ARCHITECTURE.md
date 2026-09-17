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
| テストフレームワーク | Swift Testing（XCTest は全廃済み） |
| CI | GitHub Actions (`.github/workflows/ci.yml`) |

---

## 2. モジュール構成

```text
Package.swift
 +-- RuntimeABI           (target)      Runtime ABI 契約と extern view の共有境界
 +-- CompilerCore         (library)     フロントエンド (Lex〜Lowering)、LLVM 非依存
 +-- CompilerBackend      (library)     バックエンド (Codegen + Link)、LLVM 依存
 +-- KSwiftKCLI           (executable)  CLI エントリポイント -> kswiftc
 +-- LSPServer            (library)     Language Server Protocol 実装
 +-- KSwiftLSPCLI         (executable)  LSP サーバ CLI エントリポイント -> kswift-lsp
 +-- GoldenHarnessSupport (library)     ゴールデンテスト共通ハーネス
 +-- GoldenHarnessWorker  (executable)  ゴールデンテスト実行ワーカー
 +-- CompilerTestSupport  (library)     テスト共通ヘルパー (assertion / filesystem / pipeline / KIR・LLVM)
 +-- TestStdlibCache      (library)     テスト用 bundled stdlib .kklib を 1 回だけビルドして共有する content-addressed キャッシュ
 +-- Runtime              (library)     GC / coroutine / boxing ヘルパー
```

### 依存グラフ

```text
KSwiftKCLI           --> CompilerCore, CompilerBackend
                         CompilerBackend --> CompilerCore, RuntimeABI
                         CompilerCore    --> RuntimeABI
KSwiftLSPCLI         --> LSPServer, CompilerCore, CompilerBackend
                         LSPServer       --> CompilerCore
GoldenHarnessWorker  --> GoldenHarnessSupport --> CompilerCore
CompilerTestSupport  --> CompilerCore
TestStdlibCache      --> CompilerCore, CompilerBackend
CompilerCoreTests    --> CompilerCore, CompilerTestSupport, GoldenHarnessSupport, GoldenHarnessWorker, TestStdlibCache
CompilerBackendTests --> CompilerBackend, CompilerCore, CompilerTestSupport, TestStdlibCache
RuntimeTests         --> Runtime, RuntimeABI
RuntimeTestsParallel --> Runtime, RuntimeABI
KSwiftKCLITests      --> KSwiftKCLI, CompilerCore
LSPServerTests       --> LSPServer, CompilerCore
Runtime (独立 — リンク時に結合)
```

LLVM への SwiftPM リンク依存はない。`CompilerBackend` が実行時に `libLLVM.dylib` / `libLLVM.so` を `dlopen` で動的ロードする（`Sources/CompilerBackend/LLVMCAPIBindings+Loading.swift`）。

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
| 8 | **Codegen** | KIR | `.o` / `.ll` / `.kir` / `.kklib` | `CompilerBackend/CodegenPhase.swift`, `CompilerBackend/LLVMBackend.swift`, `CompilerBackend/NativeEmitter.swift` |
| 9 | **Link** | `.o` ファイル | 実行ファイル (`swiftc` 呼び出し) | `CompilerBackend/LinkPhase.swift` |

---

## 4. ディレクトリマップ — 「どこを触るか」早見表

### `Sources/CompilerCore/` (コンパイラ本体)

| ディレクトリ | 責務 | 主要型/ファイル | 典型タスク |
|---|---|---|---|
| `Lexer/` | トークン化 | `KotlinLexer.swift`, `KotlinLexer+Strings.swift`, `KotlinLexer+Literals.swift`, `TokenModel.swift`, `TokenStream.swift` | 新リテラル追加、文字列テンプレート修正 |
| `Parser/` | CST 構築 | `KotlinParser.swift`, `KotlinParser+Declarations.swift`, `KotlinParser+Statements.swift`, `SyntaxArena.swift` | 新構文のパース対応 |
| `AST/` | CST -> AST 変換 | `BuildASTPhase+*.swift` (20+ファイル), `ASTModels.swift`, `ASTDeclModels.swift`, `ASTExprModels.swift`, `ASTArena.swift` | 新 AST ノード追加、式パーサ修正 |
| `Sema/` | 型チェック / データフロー解析 | `Infrastructure/SemaPhase.swift`, `DataFlow/Phase.swift`, `TypeCheck/TypeCheckSemaPhase.swift`, `Resolution/OverloadResolver.swift`, `Resolution/ConstraintSolver.swift`, `TypeSystem/TypeSystem.swift`, `Models/SemanticsModels.swift`, `TypeSystem/TypeModels.swift` | 型推論修正、オーバーロード解決、smart cast |
| `KIR/` | 型付き中間表現 | `KIRModels.swift`, `BuildKIRPhase.swift`, `KIRLoweringDriver.swift`, `ExprLowerer.swift`, `CallLowerer.swift`, `ControlFlowLowerer.swift`, `MemberLowerer.swift`, `LambdaLowerer.swift`, `ObjectLiteralLowerer.swift` ほか。各 Lowerer は責務ベース suffix（§4.1）で多数分割されている | IR 命令追加、コール生成修正 |
| `Lowering/` | KIR 脱糖パス群 | `LoweringPhase.swift` (パス登録) + 各 `*LoweringPass.swift`。実行順は §9 参照 | for/when/property のデシュガー修正、新 lowering pass 追加 |
| `Sema/NameMangler.swift` | マングリング | `NameMangler` | シンボル名マングリング修正 |
| `Driver/` | パイプライン制御 + 横断インフラ | `Driver.swift`, `CompilationContext.swift`, `Diagnostics.swift`, `Phases.swift`, `FrontendPhases.swift`, `SourceManager.swift`, `SourceLocation.swift`, `CommandRunner.swift`, `PhaseTimer.swift`, `IncrementalCompilationCache.swift`, `DependencyGraph.swift`, `FileFingerprint.swift` | 新フェーズ追加、診断メッセージ修正、インクリメンタルビルド |
| `Stdlib/` | Kotlin stdlib ソース（リソース） | `kotlin/collections/*.kt`, `kotlin/text/*.kt`, `kotlinx/coroutines/**/*.kt` 等（詳細は [`stdlib-pipeline.md`](stdlib-pipeline.md)） | stdlib 拡張関数の追加・修正 |

### `Sources/CompilerBackend/` (LLVM バックエンド)

| ファイル | 責務 |
|---|---|
| `BackendPhaseProvider.swift` | `makeBackendPhases()` — CodegenPhase + LinkPhase を提供 |
| `CodegenPhase.swift` | KIR → LLVM IR 変換フェーズ |
| `LinkPhase.swift` | オブジェクト → 実行ファイルリンクフェーズ |
| `LLVMBackend.swift` | LLVM バックエンドエントリ |
| `LLVMCAPIBindings.swift` (+分割6ファイル: `+Core` / `+DebugInfo` / `+IRBuilder` / `+Loading` / `+Passes` / `+TargetMachine`) | LLVM C API の Swift ラッパー。`+Loading.swift` が `libLLVM.dylib` / `libLLVM.so` を `dlopen`/`dlsym` で動的ロード |
| `NativeEmitter.swift` (+分割3ファイル: `+EmissionConstants` / `+FunctionEmission` / `+TypeLowering`) | ネイティブコード発行 |
| `LLVMEntryPointObjectEmitter.swift` | エントリポイント用オブジェクトの発行 |
| `RuntimeReflectionMetadataEmitter.swift` | `KClass` 向け実行時リフレクションメタデータを LLVM グローバル定数として発行 |
| `CodegenRuntimeSupport.swift` (+`+RuntimeObjects`) | ランタイムサポート関数 |
| `CodegenSymbolSupport.swift` | シンボルサポート |
| `StdlibArtifactCache.swift` | 実行ファイル生成時に使う stdlib `.kklib` の生成・探索（パッケージ同梱を優先、無ければユーザーキャッシュに生成） |

### `Sources/KSwiftKCLI/`

| ファイル | 責務 |
|---|---|
| `CLIParser.swift` | CLI 引数パース（`--stdlib-*` / `-g` / `-O` などのオプション定義） |
| `main.swift` | エントリポイント。パース結果から `CompilerDriver` を呼び出す |

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
| `DebounceScheduler.swift` | 遅延実行スケジューラ（テストでは決定的な実装に差し替え可能） |
| `Features/` | 機能別ハンドラ (Hover / Definition / DocumentSymbol / Diagnostics / CodeAction / SymbolResolution) |

### `Sources/KSwiftLSPCLI/`

| ファイル | 責務 |
|---|---|
| `main.swift` | LSP サーバ CLI エントリポイント |

### `Sources/Runtime/` (78 ファイル — カテゴリ別抜粋)

| カテゴリ | 主要ファイル | 責務 |
|---|---|---|
| 型・メモリ | `RuntimeTypes.swift`, `RuntimeBoxing.swift`, `RuntimeGC.swift`, `RuntimeMemory.swift`, `RuntimeMetadata.swift` | `KTypeInfo`, ヒープ管理、mark-sweep GC、ボックス型 |
| 文字列 | `RuntimeStringArray.swift`, `RuntimeStringBuilder.swift`, `RuntimeStringQuery.swift`, `RuntimeStringHOF.swift` 等 (12 ファイル) | 文字列操作・検索・変換・フォーマット |
| コレクション | `RuntimeCollections.swift`, `RuntimeCollectionHOF.swift`, `RuntimeCollectionHelpers.swift`, `RuntimeArrayBasics.swift`, `RuntimeSetAndMap.swift` 等 | 配列・リスト・セット・マップ操作 |
| Coroutine/Flow | `RuntimeCoroutine.swift`, `RuntimeCoroutineChannel.swift`, `RuntimeCoroutineContext.swift`, `RuntimeCoroutineFlow.swift` | coroutine ステートマシン、Channel、Flow |
| 数値・演算 | `RuntimeMath.swift`, `RuntimeNumericCoercion.swift`, `RuntimeNumericCompat.swift`, `RuntimeRandom.swift` | 数値変換・互換演算・乱数 |
| IO・ネットワーク | `RuntimeFileIO.swift`, `RuntimeNetwork.swift`, `RuntimeFileSystemException.swift` | ファイル IO、HTTP |
| プラットフォーム | `RuntimeHelpers.swift`, `RuntimePlatform.swift`, `RuntimeSystem.swift`, `RuntimeTime.swift`, `RuntimeInstant.swift` | ヘルパー関数、プラットフォーム検出、時間 |
| Delegate | `RuntimeDelegates.swift` | delegate プロパティランタイムサポート |
| 並行・同期 | `RuntimeAtomic.swift`, `RuntimeSync.swift`, `RuntimeThreadLocal.swift` | アトミック操作、ロック、スレッドローカル |

### `Sources/RuntimeABI/`

| ファイル | 責務 |
|---|---|
| `RuntimeABISpec.swift` | Runtime ABI 仕様定数と C ヘッダ生成 |
| `RuntimeABIExterns.swift` | `RuntimeABISpec` から導出される extern 宣言 view |

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
 |    +-- Lowering/       # LoweringPassRegressionTests+*, ...
 |    +-- Driver/         # DriverTests, DiagnosticEngineTests, SourceManagerTests, IncrementalCompilationCacheTests, ...
 |    +-- Integration/    # SmokeTests, GoldenHarnessSwiftTesting, DeepPhasePipelineIntegrationTests, FrontendParallelBenchmarkTests
 |    +-- GoldenCases/    # .kt スナップショットフィクスチャ (Lexer/, Parser/, Sema/, Diagnostics/)
 |                        #   `.golden` は生成物。`stdlib_<package path>_<Type>_<member>`
 |                        #   命名の `n` は「該当なし」。スロットの網羅は要求されない
 +-- CompilerBackendTests/     # バックエンドテスト (LLVM 必要)
 |    +-- Codegen/        # CodegenBackendIntegrationTests+*, CodegenBackendFixtureTests, LinkPhaseIntegrationTests, NameManglerTests
 |    +-- Fixtures/       # CodegenBackendFixtureTests が走査する <領域>/<ケース>/{*.kt,expected.txt}
 |    +-- Integration/    # BundledStdlibExecutionTests+*, BackendDriverOutputTests, RuntimeStubImplementationTests
 |    +-- Lowering/       # LoweringCodegenRegressionTests, VirtualDispatchTests+*, ...
 |    +-- Sema/           # LibraryMetadataImportIntegrationTests
 |    +-- KIR/            # BuildKIRRegressionTests+AbiBoxingAndArrayLowering, DelegatePropertyKIRTests, ClockNowKIRRegressionTests
 +-- RuntimeTests/            # ランタイムユニットテスト
 +-- RuntimeTestsParallel/    # ランタイム並列テスト
 +-- KSwiftKCLITests/         # CLI 統合テスト
 +-- LSPServerTests/          # LSP サーバテスト
 +-- ARCH-025/                # Kotlin compiler testData の適合サブセット台帳 (manifest.tsv / ledger.tsv / fixtures/、Scripts/*_arch025_testdata.sh で運用。swift test には接続しない)
 +-- CrashCorpus/             # mutation fuzzer のプロセス安全性オラクル用に最小化した .kt + .expect
```

### Synthetic member link tests

`Tests/CompilerCoreTests/Sema/*SyntheticMemberLinkTests*.swift` は、合成 stdlib surface がまだ存在する間の link-surface sentinel として扱う。
対応する stdlib API を Kotlin source へ移行して合成スタブを削除する PR では、同じ PR で該当 synthetic member link test も削除または source-backed assertion へ置換する。
この群は migration progress を測るための一時的な安全網なので、単独の大規模リファクタ・分割・命名整理の対象にしない。

### Codegen 実行テスト資産 (fixture 駆動)

Codegen 統合テスト（`Tests/CompilerBackendTests/Codegen/CodegenBackend*Tests.swift`）は、
Kotlin ソースを `kswiftc` でコンパイル・実行し stdout を突き合わせるものが大半で、
1 ケースにつき同型のボイラープレート（`let source = ...` / `assertKotlinOutput(...)`）が重複していた。
これを削減するため fixture 駆動ハーネス `CodegenBackendFixtureTests`
（[`../Tests/CompilerBackendTests/Codegen/CodegenBackendFixtureTests.swift`](../Tests/CompilerBackendTests/Codegen/CodegenBackendFixtureTests.swift)）を用意している。

- fixture の実体は [`../Tests/CompilerBackendTests/Fixtures/`](../Tests/CompilerBackendTests/Fixtures/) 以下に置く。
  1 fixture = 1 ディレクトリで、単一の `*.kt`（`fun main()` を持つ実行可能ソース）と
  期待 stdout の `expected.txt` を含む。領域単位でネストしてよい（例: `collections/list_sum/`）。
- ハーネスは実行時に `Fixtures/` を再帰的に走査し、`expected.txt` を持つ全ディレクトリを
  自動的に fixture として検出・実行する。`Scripts/diff_cases` と同じく「ファイルを置くだけ」で追加できる。
- `Fixtures/` は `Package.swift` の `CompilerBackendTests` ターゲットで `exclude` 指定している
  （ソース/リソースとして扱わせないため）。

> **ガイドライン: 新規 Codegen 実行テストは fixture 必須。**
> `.kt` をコンパイル・実行して stdout を比較する新規 Codegen テストは、原則として
> 個別の `CodegenBackend*Tests.swift` を新設せず、`Fixtures/` に
> `<領域>/<ケース名>/<ケース名>.kt` + `expected.txt` を追加して `CodegenBackendFixtureTests`
> に検出させる。stdout 比較に収まらない検証（KIR ダンプ・callee 検査・診断など）が必要な場合に限り
> 個別の `@Test` を書く。既存ケースの fixture 化は領域単位で順次進める。

### テストファイル名は suite 型名と一致させる

`--filter` は suite の**型名**（`@Suite struct` / XCTestCase クラス名）に掛かり、ファイル名は一切参照しない。
したがって 1 ファイル = 1 suite の場合、**ファイル名は宣言している suite 型名と同じにする**。

`Base+Suffix.swift` という名前は「`Base` の extension」を意味する場合にのみ使う。
`extension Base` を含まないのに `Base+Suffix.swift` と名付けると、
`--filter Base` がそのファイルのテストを 1 件も選ばないのに、`swift_test.sh` は
`All tests passed.` を出して exit 0 で終わる（0 件マッチはエラーにならない）ため、
未実行を成功と誤認する。`--filter` を書く前に対象ファイルの型名を確認すること:

```bash
grep -nE "@Suite|^struct|^final class|extension " <file>   # @Suite struct X は1行形式が主流
```

1 ファイルが複数 suite を宣言する場合（`RuntimeNativeConcurrentTests.swift` など）は
領域名で束ねてよい。ヘルパーのみのファイルは `Base+Helper.swift` のままでよい。

### テスト実行コマンド

```bash
bash Scripts/swift_test.sh                        # 全テスト (並列)
bash Scripts/swift_test.sh --filter CodegenBackendFixtureTests  # Codegen fixture ハーネスのみ
bash Scripts/diff_kotlinc.sh Scripts/diff_cases   # kotlinc 差分回帰テスト
```

フィルタ指定・ゴールデン更新（`UPDATE_GOLDEN=1`）・Swift 言語モード指定などの詳細は [`AGENTS.md`](../AGENTS.md) の「ビルド & テストコマンド」を参照。

### テストフレームワーク（Swift Testing）

全 target のテストは Swift Testing（`import Testing`, `@Test`, `#expect`）に統一済みで、XCTest は全廃している（`import XCTest` を新規に追加しない）。新規テストは、まず同じ target / ディレクトリの既存スタイルに合わせる。target 別の慣例:

| 用途 | 既定 |
|---|---|
| `CompilerCoreTests` の AST / Driver / Integration / Golden harness など、LLVM 非依存で値検証中心のテスト | Swift Testing suite。近接の既存 suite（`+<責務>` 分割ファイル）に追加する |
| `KSwiftKCLITests` / `LSPServerTests` の小さな protocol・parser・flow テスト | Swift Testing |
| `CompilerBackendTests` の codegen/link 実行、LLVM・subprocess・fixture cleanup に依存するテスト | Swift Testing；stdout 比較なら `Fixtures/`（上記ガイドライン）、共通 helper は assertion を持たない |
| `RuntimeTests` / `RuntimeTestsParallel` でプロセス全体の runtime state を変更 / GC するテスト | Swift Testing with `.runtimeIsolation(...)` |

共通 helper が複数 suite から必要な場合は、assertion API を持たない helper（`CompilerTestSupport` など）に切り出す。

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
    v  (Link: swiftc 呼び出し)
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
| `StringInterner` | `Lexer/TokenModel.swift`（`CompilationContext.interner` として保持） | 文字列 -> InternedString (Int32) の双方向変換 |
| `SymbolTable` | `Sema/Models/SemanticsModels.swift` | シンボル定義・FQName/ShortName 索引・関数シグネチャ・レイアウト |
| `TypeSystem` | `Sema/TypeSystem/TypeSystem.swift` | 型の登録・部分型判定・変性・置換 |
| `NameMangler` | `Sema/NameMangler.swift` | ABI 安定なマングル名生成 |
| `PhaseTimer` | `Driver/PhaseTimer.swift` | フェーズ実行時間計測 (`-Xfrontend time-phases`) |
| `IncrementalCompilationCache` | `Driver/IncrementalCompilationCache.swift` | 入力フィンガープリント + build 構成 hash による no-op output artifact 再利用、および file-level frontend state (interner + AST) の復元 |

---

## 9. Lowering パス実行順序

`Sources/CompilerCore/Lowering/LoweringPhase.swift` の `passes` 配列で定義。順序に依存関係あり:

```text
1.  TailrecLoweringPass          -- tailrec 関数のループ変換 (beginBlock に依存、NormalizeBlocks 前に実行)
2.  NormalizeBlocksPass          -- ブロック正規化
3.  OperatorLoweringPass         -- 演算子展開
4.  ForLoweringPass              -- for ループ脱糖 (iterator パターン)
5.  CollectionLiteralLoweringPass -- registry 経由のコレクションリテラル構築 + virtual call rewrite
6.  FlowLoweringPass             -- Kotlin Flow 構築・変換
7.  ValueClassUnboxingPass       -- value class のアンボクシング (PropertyLowering 前に実行)
8.  PropertyLoweringPass         -- get/set アクセサ展開
9.  JvmStaticLoweringPass        -- @JvmStatic アノテーション処理
10. JvmOverloadsLoweringPass     -- @JvmOverloads デフォルト引数オーバーロード生成
11. DataEnumSealedSynthesisPass  -- data/enum/sealed synthetic ヘルパー
12. EnumEntriesLoweringPass      -- enum entries プロパティ合成
13. ConsolePrintLoweringPass     -- print/println の引数を静的型の toString() 経由に書き換え (bundled Console.kt の Any? 受け口対策)
14. EnumNameAccessLoweringPass   -- enum name アクセスの展開
15. LambdaClosureConversionPass  -- ラムダクロージャ変換
16. InlineLoweringPass           -- inline 関数本体展開
17. CoroutineLoweringPass        -- suspend 関数 CPS 変換 + ステートマシン
18. IntegerNarrowingPass         -- 整数型ナローイング (整数演算 builtin を出す全パスの後、ABILowering の前)
19. ABILoweringPass              -- outThrown チャネル設定
```

`lazy` / `Delegates.observable` / `vetoable` の delegate lowering は KSP-491 で Kotlin ソース化され、専用パス（旧 `StdlibDelegateLoweringPass`）は削除済み。

`CoroutineLoweringPass` は `CoroutineLoweringPass.swift` 本体と、責務別に分割された 7 個の extension ファイル
(`+Analysis`, `+CallRewriting`, `+Flow`, `+FlowInstructionRewrite`, `+LauncherSupport`, `+StateMachine`, `+Synthesis`) で構成される。

---

## 10. CI ジョブ構成

`.github/workflows/ci.yml` のジョブ（全ジョブ `ubuntu-latest`、Swift 6.3、`SWIFT_BUILD_SYSTEM=native`、`SWIFT_XSWIFTC_FLAGS` で言語モード 6 + strict concurrency を共有）:

| ジョブ | 内容 |
|---|---|
| `verify-todo-ids` | `Scripts/check_todo_ids.sh` で `TODO.md` のタスク ID 重複チェック |
| `build-debug-tests` | `Scripts/build_swift_tests.sh` でコンパイラと全テストターゲットをデバッグビルドし、`swift-debug-tests-<run id>` artifact にする（1 回だけ） |
| `verify-core` | `build-debug-tests` の成果物を展開し、`CompilerCoreTests` をメソッド単位の動的シャード（6 分割）で実行。Golden 4 スイートは `KSWIFTK_GOLDEN_SHARD_INDEX/COUNT` で分割。shard 1 だけ `SmokeTests` と `FrontendParallelBenchmarkTests` も実行。LLVM 不要 |
| `verify-self-hosted` | 同じ成果物で `CompilerBackendTests` を静的シャード（4 分割）で実行。shard 1 だけ `RuntimeTests`（直列・チャンク）/ `RuntimeTestsParallel` / `KSwiftKCLITests` / `LSPServerTests` も実行。`setup-llvm` で LLVM を導入 |
| `verify-repository-checks` | `Scripts/loc_report.sh`（artifact `refactoring-metrics-<run id>`）と `jscpd --config .jscpd-ci.json`（閾値超過で失敗） |
| `build-release-kswiftc` | `swift build -c release --product kswiftc` を 1 回だけ実行し `kswiftc-release-<run id>` artifact にする |
| `verify-diff` | release `kswiftc` を展開し、JDK 21 + kotlinc 2.3.10 で `Scripts/diff_kotlinc.sh` を 4 シャード実行。shard 1 は `Scripts/diff_diagnostics.sh` も実行。失敗時は `kotlinc-diff-regression-<run id>-shard-<n>` artifact |

セットアップアクション（`.github/actions/`）:
- [`setup-self-hosted`](../.github/actions/setup-self-hosted/action.yml) — Linux ランナーの共通準備（全ジョブ）
- [`setup-swift`](../.github/actions/setup-swift/action.yml) — 指定バージョン（6.3）の Swift ツールチェーンを用意し、バージョン一致を検証
- [`setup-llvm`](../.github/actions/setup-llvm/action.yml) — `llvm-dev` を導入し `llvm-config` から `KSWIFTK_LLVM_DYLIB` 等を導出（`verify-self-hosted` のみ）
- [`setup-swiftpm-cache`](../.github/actions/setup-swiftpm-cache/action.yml) — `.build` を actions/cache から復元。`build-debug-tests` / `build-release-kswiftc` が `save: "false"`（restore-only）で使用

LLVM を明示的に導入するのは `verify-self-hosted` だけ。`verify-diff` は `setup-llvm` を使わず、release `kswiftc` が実行時に `KSWIFTK_LLVM_DYLIB` または既定候補パスから `libLLVM` を `dlopen` する（§2）。

### ビルドとテスト実行の分離

テストのビルドは `build-debug-tests` の 1 回だけで、`verify-core` / `verify-self-hosted` は artifact を展開して `swift test --skip-build`（`Scripts/swift_test.sh --skip-build` / `Scripts/shard_swift_tests.sh`）で実行する。ビルド時と `--skip-build` 時で `-Xswiftc` フラグが一致しないと incremental cache が無効化されるため、各ジョブは同一の `SWIFT_XSWIFTC_FLAGS` を共有する。

`Scripts/build_swift_tests.sh` は既定で `swift build --build-tests` を実行する。`SWIFT_TEST_BUILD_TARGETS` を指定するとそのターゲットだけを `swift build --target <T>` で 1 つずつビルドする（SwiftPM の `--target` は累積しないためループ処理）。Swift 6.3 の `swiftbuild` ビルドシステム（`SWIFT_BUILD_SYSTEM=swiftbuild`）にも対応しており、その場合はテストターゲットごとの `<Target>-test-runner` プロダクトを `swift test --skip-build --test-product <Target>` で個別実行できる（`swift_test.sh` / `shard_swift_tests.sh` は `SWIFT_TEST_PRODUCT` または `--target-prefix` から `--test-product` を自動付加）。ただし Linux での断続的なクラッシュ（SIGSEGV/SIGBUS/SIGILL）を避けるため、CI は `native` を使う。

### コンパイルキャッシュ

`SWIFT_ENABLE_COMPILE_CACHE=1` を設定すると、`Scripts/lib/common.sh` が `-Xswiftc -explicit-module-build -Xswiftc -cache-compile-job -Xswiftc -cas-path -Xswiftc <SWIFT_CAS_PATH>` を `build_swift_tests.sh` と `swift_test.sh` / `shard_swift_tests.sh` に渡す。`-explicit-module-build` は必須で、これがないと swift-driver が `warning: -cache-compile-job cannot be used without explicit module build, turn off caching` を出してキャッシュを**黙って無効化**する（ビルド自体は成功する）。`build_swift_tests.sh` はこの警告を検出するとビルドを失敗させる。

CI では `build-debug-tests` / `verify-core` / `verify-self-hosted` が `SWIFT_ENABLE_COMPILE_CACHE=1` と `SWIFT_CAS_PATH=.build/out/CompilationCache.noindex` を設定する。`setup-swiftpm-cache` は現在 restore-only（`save: "false"`）で呼ばれているため、CAS を含む `.build` が actions/cache に保存されるのは同アクションを `save: "true"` で呼ぶ run に限られる（現行の `ci.yml` にはない）。

`swiftbuild` を使う場合は、`kswiftk_setup_compile_cache_env` が `EnableSwiftCachingByDefault=true` / `EnableClangCachingByDefault=true` / `EnableSwiftExplicitModulesByDefault=true` を追加でエクスポートし、`.build/out/CompilationCache.noindex` / `ModuleCache.noindex` に成果物を蓄える。ローカル計測例（Swift 6.3.1、`CompilerCoreTests-test-runner`）: キャッシュなし初回ビルド約 170 秒、復元後の再ビルド約 7 秒。

計測用に `SWIFT_ENABLE_CACHE_REMARKS=1` を設定すると `-Rcache-compile-job` が付与され、ビルドログから cache hit/miss の確認ができる。

### CI 失敗時のデバッグ（短い手順）

- **kotlinc diff が落ちた場合**: `verify-diff` ジョブの **Summary**（`Scripts/diff_kotlinc_ci_summary.sh` が生成）と **Artifacts**（`kotlinc-diff-regression-<run id>-shard-<n>`、TSV と失敗ケースディレクトリ）を確認。全文ログでは `FAIL ` で検索。`gh run view <id> --log-failed` だけでは、`continue-on-error` により diff 本体のステップが「失敗扱い」にならず **差分ログが出ない**ことがある。
- **テスト / スモーク**: 各 verify ジョブの Summary（"Reproduce hints"）にローカル再現用コマンドを記載。`jscpd` 失敗時も `verify-repository-checks` の Summary に再現コマンドを追記。

---

## 11. タスク別ナビゲーション — どこを見るか

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

1. `CompilerBackend/LLVMBackend.swift` — LLVM バックエンド初期化・エラーハンドリング
2. `CompilerBackend/NativeEmitter.swift` + `NativeEmitter+FunctionEmission.swift` — KIR → LLVM IR エミッション
3. `CompilerBackend/CodegenPhase.swift` — Codegen フェーズ制御、emit モード分岐
4. `CompilerBackend/LinkPhase.swift` — リンクコマンド構築、エントリラッパー生成
5. `CompilerCore/Sema/NameMangler.swift` — シンボル名マングリング
6. `RuntimeABI/RuntimeABIExterns.swift` — ランタイム ABI extern view

### ランタイム動作のバグを直す

1. `Sources/Runtime/` 配下の該当ファイル
2. `RuntimeStringArray.swift` — `__kk_println_raw` 等の出力系（`print`/`println` 本体は bundled Kotlin ソース `Stdlib/kotlin/io/Console.kt` 側）
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
| Codegen 実行テスト (fixture) | `Tests/CompilerBackendTests/Fixtures/<領域>/<ケース>/{*.kt,expected.txt}` | `bash Scripts/swift_test.sh --filter CodegenBackendFixtureTests` |
| E2E スモークテスト | `Tests/CompilerCoreTests/Integration/SmokeTests.swift` | `bash Scripts/swift_test.sh --filter SmokeTests` |

---

## 12. 主要な型 ID 一覧

コードベース全体で使われる ID 型。すべて `Int32` ベース、無効値は `-1`。

| ID 型 | 定義場所 | 用途 |
|---|---|---|
| `FileID` | `Driver/SourceLocation.swift` | ソースファイル識別 |
| `InternedString` | `Lexer/TokenModel.swift` | インターン済み文字列 |
| `NodeID` | `Driver/SourceLocation.swift` | CST ノード |
| `TokenID` | `Driver/SourceLocation.swift` | CST トークン |
| `DeclID` | `Driver/SourceLocation.swift` | AST 宣言 |
| `ExprID` | `AST/ASTModels.swift` | AST 式 |
| `TypeRefID` | `AST/ASTModels.swift` | AST 型参照 |
| `SymbolID` | `Sema/Models/SemanticsModels.swift` | 意味解析シンボル |
| `TypeID` | `Sema/TypeSystem/TypeModels.swift` | 型システム内の型 |
| `KIRDeclID` | `KIR/KIRModels.swift` | KIR 宣言 |
| `KIRExprID` | `KIR/KIRModels.swift` | KIR 式/レジスタ |

---

## 13. ライブラリ配布形式 (.kklib)

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
manifest スキーマ・metadata.bin の詳細仕様は [`docs/spec.md`](spec.md) Doc J14 を正とする。

---

## 14. 並列処理

フロントエンドフェーズ (Lex, Parse, BuildAST) はファイル単位で並列実行可能:

- `-Xfrontend jobs=N` で並列度を指定
- `DispatchQueue.concurrentPerform` で並列化し、`DispatchSemaphore` / `DispatchGroup` で並列度を制御（`Driver/FrontendPhases.swift`）
- 並列実行後は `FileID` 順でソートし決定性を保証
- 診断メッセージも `sortBySourceLocation()` でソース位置順に安定化
