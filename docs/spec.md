# 実装仕様（API レベル）

実装レベルの API 仕様（Swift の型・関数・データフォーマットまで固定）を Phase ごとに "Doc" として提示する。これだけを参照すれば、外部ドキュメントを読まずとも（曖昧点は `kotlinc` による差分テストで確定させる前提で）完成まで走れる粒度を目指す。

監査メモ（2026-07-02）：

* この文書内の repo 内ファイル参照は、コード例の架空入力ファイルを除き、実在パスとして確認する。
* 実装が先行している API では、該当する Sources 配下のファイルを source of truth とし、本書は現行の public surface と設計意図を同期する。
* VS Code など個人 IDE 設定は追跡対象にしない。

前提（この仕様書で固定する基準）：

* **Kotlin 2.4.20 の stable 範囲**を対象（公式 Grammar は “latest stable で experimental 無効ルール除外” を明示） ([Kotlin][1])
* セマンティクスは Kotlin/Core を基準（式・宣言・型・オーバーロード解決） ([Kotlin][2])
* Coroutines は Kotlin spec の CPS 変換モデルを実装（`Continuation<T>` 追加引数 + `Any?` 戻り、suspend/return 判定） ([Kotlin][3])
* 実行環境は **macOS のみ**。開発は Xcode 26（Swift 6.2）を基準 ([Apple Developer][4])

---

# Doc J0: 実装方針と “規約” 固定（全 Phase 共通）

## J0.1 リポジトリ規約（必須）

* すべて SwiftPM パッケージ。
* すべてのモジュールは `public` API を最小にし、内部は `internal` に閉じる。
* すべての “ID” は整数で表し、参照は **インターン（intern）**で統一（String/Type/Symbol を直接比較しない）。

## J0.2 コンパイラの決定性（必須）

同一入力・同一オプションで出力がビットレベルで一致する（DWARF を除く）こと。

* HashMap の iteration 順に依存しない（ソートして出す）。
* 乱数禁止。

## J0.3 エラー耐性（必須）

* どんな入力でもクラッシュしない。
* `fatalError` は “内部不整合（ICE）” のみに限定し、必ず `KSWIFTK-ICE-xxxx` を出す。

## J0.4 Kotlin 2.3 の安定機能差分（注意点）

Kotlin 2.3.0 で stable 化／既定有効化された要素は互換対象：

* **nested type aliases**
* **when の data-flow ベース exhaustiveness**
* **明示戻り型がある expression body で `return` 許可（既定有効）** ([Kotlin][5])

この仕様書ではこれらを “必須” とし、テストで保証する。

---

# Doc J1: Driver / コンパイルモデル（`KSwiftKCLI` + `CompilerCore`）

## J1.1 主要型（Swift）

現行の public compiler option surface は `Sources/CompilerCore/Sema/Models/CompilerTypes.swift` を正とする。

```swift
public struct TargetTriple: Equatable {
    public let arch: String         // "arm64" or "x86_64" in supported hosts
    public let vendor: String       // "apple" or "unknown"
    public let os: String           // "macosx" or "linux-gnu"
    public let osVersion: String?   // optional

    public static func hostDefault() -> TargetTriple
}

public enum OptimizationLevel: Int { case O0, O1, O2, O3 }
public enum EmitMode: String { case executable, object, llvmIR, kirDump, library, jvmClass, jvmJar }
public enum DiagnosticsFormat: String { case text, json }

public struct CompilerOptions: Equatable {
    public var moduleName: String
    public var inputs: [String]              // .kt paths
    public var outputPath: String
    public var emit: EmitMode
    public var searchPaths: [String]         // -I
    public var libraryPaths: [String]        // -L
    public var linkLibraries: [String]       // -l
    public var target: TargetTriple
    public var optLevel: OptimizationLevel
    public var debugInfo: Bool               // -g
    public var frontendFlags: [String]
    public var irFlags: [String]
    public var runtimeFlags: [String]
    public var diagnosticsFormat: DiagnosticsFormat
    public var stdlibSearchPaths: [String]
    public var includeStdlib: Bool
    public var incrementalCachePath: String?
    public var entryPointFQName: String?     // exact file-level executable entry

    /// When true, compile only the bundled/residual stdlib into a .kklib.
    public var stdlibOnly: Bool
    /// Path to a prebuilt stdlib .kklib. Disables bundled source injection.
    public var stdlibLibraryPath: String?
    /// Search paths ordered with stdlibLibraryPath first and duplicates removed.
    public var effectiveLibrarySearchPaths: [String]

    public static func defaultStdlibSearchPaths() -> [String]
}
```

## J1.2 コンパイルの “単位”

実験的な JVM M22 は `--emit class|jar` で選択する。Native の KIR・ABI lowering
の前で分岐し、既存 Parser／AST／Sema と JVM 用 console／classpath 宣言を使う。
`--classpath` の公開 JVM signature を解決し、foreign invocation と Kotlin metadata／module を生成する。
`JVMSourceValidationPhase` が対応文法、`JVMFrontendPhase` が型付き JVM IR を検査・構築し、
`JVMCodegenPhase` が facade と各 class／interface の classfile、検証用 StackMapTable を生成する。
クラスの constructor／field／accessor、継承と動的ディスパッチ、共変 override の bridge、
Kotlin class metadata を生成する。M5 は非 reified ジェネリクスの型消去・Signature／metadata、
JVM 配列命令、JDK List／Set／Map、exception table と finally の制御フローを追加する。
M6 は Function0〜22 ABI のラムダクラスと同一 owner の static 本体、共有セルによる可変 capture、
関数型の引数・戻り値・プロパティ、receiver 付き関数型、トップレベル／メンバー拡張関数を追加する。
関数型と拡張 receiver は Signature／Kotlin metadata に保持する。実行に必要な Function interface と
Unit singleton を同梱し、Java／公式 Kotlin の関数 ABI と互換にする。
配列 initializer と Iterable／配列の map／filter／forEach／fold も生成する。
M7 は SAM adapter、AST の inline 展開（局所／非局所 return、noinline／crossinline）、
inline／fun interface／suspend metadata を追加する。suspend は Continuation 引数／Object 戻り値へ変換し、
呼び出しごとの ContinuationImpl 状態クラスと owner 内の再開 worker がローカルと制御フローを保持する。
標準 kotlin-stdlib の SafeContinuation／Result と接続し、実際の中断・再開、例外、suspend main を実行する。
状態機械へ変換した後も method descriptor の重複を検査する。suspend inline、通常クラスの未初期化の
コンストラクタ引数からの中断、独自 CoroutineContext 実装は診断して拒否する。
M8 は名前付き object／companion の singleton とクラス初期化、data class の component／copy・default mask／
equals／hashCode／toString、java.lang.Enum の定数・定数別サブクラス／values／valueOf／entries を生成する。
sealed／nested の型関係、InnerClasses 属性、Kotlin metadata の data／enum／object／companion／sealed と
直接の sealed subclasses を保持する。Java 8 の private access は synthetic accessor／constructor bridge で接続する。
when の subject は一度評価し、各条件を順に判定する。data の destructuring も component 呼び出しへ変換する。
M9 は匿名 object を生成し、immutable capture／共有可変セル／外側 receiver をインスタンスの synthetic field に保持する。
capture と inner class の this$0 は super 呼び出し前に設定し、基底初期化中の virtual dispatch にも対応する。
共有 Sema は公開 API の推論された匿名型を単一 supertype／Any に変換し、private／local は具体型を保持する。
配列 constructor の size／init の名前を解決し、両 backend で記述順に評価する。
inner constructor の descriptor は先頭に outer を持ち、Signature／metadata では source parameter と区別する。
data object は型による equals、FQ name の固定 hash、単純名の toString を持ち、継承した final method を保持する。
名前付き引数は明示引数を記述順に一度評価して並べ替える。省略引数は宣言順に評価する mask bridge とし、
function$default／mask + DefaultConstructorMarker constructor、複数 mask、primary の全省略時の noarg、
継承既定値、extension／inline／suspend、object／enum の super 呼び出しにも接続する。
suspend default ABI は Continuation を mask／handler の前に置く。inline default bridge は本文も展開し、
mask branch と default lambda の代入を公式 Kotlin の bytecode inliner が扱う形式で生成する。
対応構文・出力規約・制限は
[`docs/jvm-backend.md`](jvm-backend.md) を参照。

M10 は interface の `by` を専用フィールドへ保存し、解決済みの forwarding symbol に対応する
メソッド／property accessor と generic bridge を生成する。delegate 式は supertype の記述順に一度だけ評価する。
メンバー／トップレベル／ローカルの委譲 property は保存した delegate に対し、共有 Sema が選択した
getValue／setValue／provideDelegate を呼ぶ。member／extension operator、ReadOnlyProperty／ReadWriteProperty、
Delegates.notNull／observable／vetoable、mutable property token を扱う。
トップレベル property は facade の static field／accessor／clinit と package metadata へ出力する。
Lazy は独自stdlibのKotlinソース実装に接続し、3種の thread safety mode、lock overload、初期化例外後の再試行、
nullable 結果を保持する。lateinit は null sentinel を読み、未初期化なら標準の
UninitializedPropertyAccessException を投げる。ローカルは capture 可能な共有セルを使い、
member／top-level の property literal に対する isInitialized は getter を通さず backing field を検査する。
Java 8 の private static／instance field access は必要に応じて synthetic accessor を生成する。
Lazy／property token／lateinit例外も独自JARから供給する。

M11 は value class の boxed IR から公開 unboxed ABI adapter を生成し、公式の名前修飾、
constructor-impl／box-impl／unbox-impl／equals-impl0 と Kotlin metadata を出力する。
box-impl は保存専用 constructor を使い、init を再実行しない。nullable reference underlying と nullable boxed value を区別する。
通常の constructor が value parameter を持つ場合は metadata を marker 付き公開 signature に対応させる。
callable reference の signature は ABI lowering 後に解決し、ldc class literal はクラスを初期化しない。
typealias は source の型パラメータ・展開型を metadata に保存する。
annotation class は Java annotation interface、定数・enum・KClass・nested／array の element_value、
AnnotationDefault、retention／target／parameter／property carrier を生成する。const field は ConstantValue を持つ。
KClass／KCallable／KProperty と kotlin.reflect.full の対応 API は独自stdlibのJava reflection／metadata readerに接続する。
M12 は generic value class の保存値を宣言上の上限型へ消去し、nullable ABI を保存値の nullability で決める。
field／getter／constructor-impl と公開 adapter の Signature は型変数と underlying の型引数を保持する。
closure と匿名 object の capture は boxed の内部 layout を保つ。
Kotlin Repeatable はネストした Container annotation と Java Repeatable、RepeatableContainer marker を生成し、
複数使用を container の annotation 配列へ格納する。JvmRepeatable は source の明示 container を使い、
value 配列、他の要素の既定値、retention、target 集合を検査する。両指定時は明示 container を優先する。
findAnnotationsは独自metadata／annotation実装、Class.getAnnotationsByTypeはJDKへ接続する。
M13 は配列と別の value class を保存値として扱う。保存 field と公開 ABI は nullable の区別を保って再帰的に
flatten し、内部 IR の field read／write には box／unbox 変換を挿入する。underlying getter は instance のまま
戻り値をマングリングする。配列の equals は参照比較、hashCode／toString は Arrays の実装を使う。
primary／secondary constructor は constructor-impl、既定引数は mask と DefaultConstructorMarker を持つ
constructor-impl$default として公開する。source constructor の metadata は secondary／optional flags を保つ。
内部 constructor が保存専用 constructor と衝突する場合は隠し引数を付け、box-impl は init を実行しない。
Sema の value-class secondary 制限は JVM 出力だけ解除する。
M14 は value class を引数／戻り値に持つ inline と suspend の公開 ABI を生成する。
inline adapter は本体の local／label／handler を写し、return を unbox する。callback invoke を公開 bytecode に
残すため、公式 Kotlin consumer の bytecode inliner も non-local return と finally を展開できる。
suspend は引数を flatten し、mangling に Continuation を含め、Continuation の Signature には logical result を保存する。
primitive underlying は同期復帰でも boxed、reference underlying は同期復帰だけ raw storage、resume は boxed とする。
coroutine worker 内部は logical box を維持し、公開 wrapper／default bridge の同期 return を変換する。
interface adapter が公開 suspend を呼ぶ場合は同期結果を rebox し、resume と同じ形へ合流する。
suspend callable reference は Continuation 込みの FunctionN と KCallables.callSuspend を使う。
value-class constructor は内部 box の allocate を引数評価後へ置くため、引数内で suspend できる。
M15 は inline suspend の通常 coroutine entry と未 lower の $$forInline 本体を生成する。
reified inline suspend は metadata と marker を持つ未 lower 本体を公開する。
suspend 呼び出しには InlineMarker 0／1、reference value-class の resume unbox には 8／9 を出力する。
既定引数 stub にも未 lower 本体を置き、公式 Kotlin consumer の coroutine inliner が展開する。
reified 型引数はソース内で具体化し、公開 inline bytecode は Intrinsics.reifiedOperationMarker と
型パラメータ metadata の reified flag を使う。is／as／as?／T::class／generic array を扱う。
escaping lambda は解決した Class と nullable 判定を capture し、lifted helper 内へ渡す。
M16 は reified callable reference の期待型／receiverから得た型引数を使い、専門化した本体のhelperを生成する。
通常のinvokeはhelperを呼び、FunctionReferenceImplには元関数の名前・Signature・ownerを保持する。
既定引数省略、Unit変換、suspend変換を伴う参照はAdaptedFunctionReferenceと適切なflagsを使う。
外側のreified型はClassとnullable情報をcaptureし、既定引数式、nested lambda、suspend復帰でも維持する。
匿名objectは同じ情報をconstructor引数とfieldへ保存し、initializer/getter/methodへ復元する。
公開inlineの匿名objectはアクセス可能なbaseとsiteごとのsubclassを持ち、必要なneedClassReification markerにより
公式Kotlin consumerでもcall siteごとにclassを生成する。通常値とmutable cellのcaptureはlexicalな消去型で揃える。
M17 は JVMValueType に Byte／Short／Char とunsigned scalar、unsignedArrayを保持する。
scalarのdescriptorとoperand stack型を分離し、B／S／Cのload/store、narrowingとboxingを生成する。
unsignedの昇格・除算・比較・shiftと飽和変換は符号なしの意味を保つ。
unsignedの公開ABIはKotlinの論理型metadata・名修飾・default／constructor bridgeを保持する。
unsigned配列はtyped codeでraw primitive array、erased codeで独自stdlibのvalue-class wrapperを使い、
coroutine lowering後にnullable変換を展開して同期return／遅延resumeのnullを維持する。
M18 は stringTemplate と String の +／+= を StringBuilder の逐次 append へ変換する。
各補間式の評価直後に文字列化し、Unit・null・unsigned・value class・配列の表示規則を保つ。
文字列操作の Sema 宣言と JVM 呼出し signature は JVMTextOperation の表から生成する。
length／indexing／反復は UTF-16 code unit を使い、Unicode trim・split・replace は独自stdlib、
大小文字変換は Locale.ROOT、数値変換はJDKと独自stdlibの検査へ接続する。
引数はソース順に一度だけ評価し、既定引数と spread のコピー時点を維持する。
StringBuilder の値は通常の JVM IR の local として inline／suspend／capture を通過する。
M19 は Regex／MatchResult／Sequence を独自stdlib、StringBuilder を JDK の ABI へ接続する。
JVMTextLibraryMethod は receiver、parameter mapping、default bridge と実在する descriptor を保持し、
Kotlin 拡張と Java member の named argument の違いも検査する。
StringBuilder の appendLine／appendRange 等と private InlineOnly な Destructured.componentN は公開 JDK／stdlib API へ展開する。
JVMTextHigherOrderDeclarations の実体付き inline 宣言を既存 inline 展開へ登録し、
非ローカル return、receiver lambda、capture、suspend、公開 inline consumer を同じ経路で扱う。
UTF-16 Char と可変 CharSequence の反復規則を保ち、filter／reduce／windowed 等の終端は公式 API と同じ時点で取得する。
非 inline の windowed／chunked／Regex.replace(transform) は boxed FunctionN で独自stdlibを呼ぶ。
M20 は Pair を公式 kotlin.Pair の descriptor／generic signature／metadata に揃え、
Map factory、to、constructor／copy／component／getter を同じ ABI で扱う。
JVMCollectionDeclarations の groupBy／associate 系／partition／zip と inline terminal を実体付き source body として展開する。
Sequence の中間操作、生成関数、joinToString 等は公式 facade の実在する descriptor／default bridge へ接続する。
SemaModule.requiresResolvedLibraryCalls は JVM のときだけ有効とし、対応 API の型推論を通常の source overload 解決へ渡す。
Native の型だけを返す collection fallback はこの経路で使用しない。引数名・generic bound・inline/crossinline と call binding を保持する。
vararg factory は各 spread をソース順に snapshot し、全引数の評価後に独自stdlibのfactoryを呼ぶ。
単一引数の非 vararg overload、Pair の分解代入、membership の container→element 評価順も保持する。
M21 は sequence／iterator builder を公式 SequencesKt、yield／yieldAll を SequenceScope の suspend ABI に接続する。
JVMTextLibrary は論理引数・戻り値のまま suspend 呼び出しを記録し、既存 coroutine lowering が Continuation と Object 戻り値へ変換する。
builder は Function2 として渡し、反復ごとの独立した frame、capture、ループ、例外 handler と finally を保持する。
型推論後に JVM 専用の SequenceScope suspension 検査を行い、同じ receiver への member／extension 呼び出しだけを許可する。
Native の suspension 検査・builder lowering は維持する。
M22 は複数ソースを一つの module として Sema で解決し、ファイルごとの facade／package metadata を出力する。
`--stdlib-only --emit jar` は共通の `kotlin/Pair/Pair.kt` と `Stdlib/jvm/` の platform source profile を
コンパイルし、`kswiftk-stdlib.jar` を生成する。Native の bundled source 列挙は `jvm/` を除外する。
Pair の data ABI、println／print、empty／singleton／vararg の List／Set／Map factory は
公式 stdlib なしで動作する。コレクションの backing object は JDK の実装を使う。
組み込み型用 `.kotlin_builtins` と Kotlin consumer 向け最小 Intrinsics は独自生成し、公式 JAR をコピーしない。
source vararg は単独 parameter の関数を扱い、配列 descriptor／generic signature／vararg metadata と spread を保持する。
複数 main、重複 facade、二つ目以降の入力の不正構文も出力前に拒否する。
このprofileは対応済みのSequence／Regex／unsigned／coroutine／reflection／lazyも含み、公式stdlib／reflect JARの実行時依存を持たない。
ABI照合はvalue-class／JvmName lowering後の公開signatureで行い、静的closure検査と独自JARだけの実行を別々に検証する。
通常の関数参照invokeはInvocationTargetExceptionを解除し、KCallable.callはJava reflectionの例外ラッパーを保持する。
対応範囲・実行例・明示的な未対応制限は docs/jvm-backend.md の M11〜M22 節を参照する。



インクリメンタルコンパイルは stdlib artifact（`.kklib`）または `--no-stdlib` を使う
非 JVM コンパイルで既定で有効。bundled stdlib をソース注入するコンパイル
（`includeStdlib` 解決後）と `--stdlib-only`、JVM 出力は既定オフのまま。
CLI の `--incremental` は `incremental` frontend flag、`--incremental-cache <path>` は
`incrementalCachePath` を設定し、それぞれ単独で有効化する（既定対象外の経路を含む）。
`--no-incremental` は `no-incremental` frontend flag を設定し、指定順に関係なく
有効化 flag と保存先指定に優先する。Driver は無効化時にキャッシュを読み書きしない。
`-Xfrontend incremental` は互換のため引き続き利用可能。
ヒット率は `-Xfrontend incremental-stats` が `incremental: runs=… restored=…` を
stderr に出力し、`time-phases` は `incremental-prepare` サブフェーズを計測する。
詳細と既定範囲の根拠は [`incremental-compilation.md`](incremental-compilation.md) を参照。

* **CompilationSession**: 1回の `kswiftc` 実行
* **Module**: Kotlin の “名前空間 + 生成物” 単位（`moduleName`）
* **Library**: 別 Module を import 可能にする配布形態（Doc J12）

`kswiftc --test`（別名 `-generate-test-runner`）は `generate-test-runner`
frontend flag を有効にする。Driver は Sema で元の入力にある `kotlin.test`
注釈を解決し、元ファイルのメモリ内コピーへ wrapper を挿入して通常のパイプラインを
再実行する。元の `main` は保持し、`entryPointFQName` で生成 entry を Link と
top-level initializer 注入の対象に指定する。指定 entry がない場合は通常 main へ
fallback しない。overlay の incremental cache は無効にする。
発見対象、ライフサイクル、失敗レポートと終了コードは
[`kotlin-test-runner.md`](kotlin-test-runner.md) を参照。

## J1.3 パイプライン API（固定）

`CompilerDriver` は `Sources/CompilerCore/Driver/Driver.swift` にあり、backend phase は `CompilerBackend` 側から注入する。

```swift
public final class CompilerDriver {
    public init(backendPhases: @escaping @Sendable () -> [CompilerPhase] = { [] })

    public func run(options: CompilerOptions) -> Int  // exit code
}

public final class CompilationContext: @unchecked Sendable {
    public let options: CompilerOptions
    public let sourceManager: SourceManager
    public let diagnostics: DiagnosticEngine
    public let interner: StringInterner

    public internal(set) var tokens: [Token] = []
    public internal(set) var tokensByFile: [(FileID, [Token])] = []
    public internal(set) var syntaxTree: SyntaxArena? = nil
    public internal(set) var syntaxTreeRoot: NodeID = .init()
    public internal(set) var syntaxTrees: [(FileID, SyntaxArena, NodeID)] = []
    public internal(set) var ast: ASTModule? = nil
    public internal(set) var sema: SemaModule? = nil
    public internal(set) var kir: KIRModule? = nil
    public internal(set) var generatedObjectPath: String? = nil
    public internal(set) var generatedLLVMIRPath: String? = nil
}
```

上記 `CompilationContext` はコアフィールドの抜粋。incremental compilation 系
（`incrementalCache` / `incrementalRecompileSet` / `incrementalFrontendState` 等）や `phaseTimer` を含む
全フィールドは `Sources/CompilerCore/Driver/CompilationContext.swift` を正とする。

## J1.4 Phase 実行プロトコル

```swift
public protocol CompilerPhase {
    static var name: String { get }
    func run(_ ctx: CompilationContext) throws
}
```

* `CompilerDriver` は以下順で frontend/core Phase を実行し、失敗時は診断を出して停止：

  1. LoadSources
  2. Lex
  3. Parse
  4. BuildAST
  5. Sema
  6. BuildKIR
  7. Lowering

* `emit == .kirDump` では driver が KIR dump を直接書き出す。
* それ以外の backend は `Sources/CompilerBackend/BackendPhaseProvider.swift` の `makeBackendPhases()` が `Codegen` → `Link` を追加する。`Link` は `emit == .executable` の場合だけ動く。

---

# Doc J2: SourceManager / 位置情報 / 診断（`CompilerCore`）

## J2.1 位置情報（必須）

Kotlin の診断は 1-indexed line/column で表示。

```swift
public struct FileID: Hashable { public let rawValue: Int }

public struct SourceLocation: Equatable {
    public let file: FileID
    public let offset: Int   // UTF-8 byte offset
}

public struct SourceRange: Equatable {
    public let start: SourceLocation
    public let end: SourceLocation
}

public struct LineColumn: Equatable {
    public let line: Int     // 1-based
    public let column: Int   // 1-based (unicode scalar count)
}
```

## J2.2 SourceManager

```swift
public final class SourceManager {
    public func addFile(path: String, contents: Data) -> FileID
    public func addFile(path: String) throws -> FileID

    public func contents(of file: FileID) -> Data
    public func path(of file: FileID) -> String

    public func lineColumn(of loc: SourceLocation) -> LineColumn
    public func slice(_ range: SourceRange) -> Substring
}
```

必須要件：

* UTF-8 を内部表現として保持。
* `lineColumn` は改行インデックスを前計算（`[Int] lineStartOffsets`）して O(log N) で求める。

## J2.3 DiagnosticEngine

現行実装は `Sources/CompilerCore/Driver/Diagnostics.swift`。

```swift
public enum DiagnosticSeverity { case error, warning, note, info }

public struct Diagnostic: Equatable {
    public let severity: DiagnosticSeverity
    public let code: String              // "KSWIFTK-PARSE-0001"
    public let message: String
    public let primaryRange: SourceRange?
    public let secondaryRanges: [SourceRange]
    public let codeActions: [DiagnosticCodeAction]
}

public final class DiagnosticEngine: @unchecked Sendable {
    public static let defaultMaxDiagnosticsPerFile: Int   // 1_000
    public var diagnostics: [Diagnostic] { get }

    public init(maxDiagnosticsPerFile: Int = defaultMaxDiagnosticsPerFile)

    public func emit(_ d: Diagnostic)
    public func error(_ code: String, _ message: String, range: SourceRange?, codeActions: [DiagnosticCodeAction])
    public func warning(_ code: String, _ message: String, range: SourceRange?, codeActions: [DiagnosticCodeAction])
    public func note(_ code: String, _ message: String, range: SourceRange?, codeActions: [DiagnosticCodeAction])
    public func info(_ code: String, _ message: String, range: SourceRange?, codeActions: [DiagnosticCodeAction])
    public var hasError: Bool { get }
    public var hasWarning: Bool { get }
    public var hasNote: Bool { get }
    public var hasInfo: Bool { get }
    public var errorCount: Int { get }
    public var warningCount: Int { get }
    public var noteCount: Int { get }
    public var infoCount: Int { get }
    public var count: Int { get }

    public func addSuppression(code: String, range: SourceRange)
    public func truncate(to count: Int)
    public func sortBySourceLocation()
    public func render(_ sourceManager: SourceManager) -> String
    public func printDiagnostics(format: DiagnosticsFormat, from sourceManager: SourceManager)
}
```

表示フォーマットは human-readable text と LSP-compatible JSON（`DiagnosticsFormat`）を持つ。

重複検査は `Set` による平均 O(1) で、ファイル (`primaryRange.start.file`、range なしは共通バケット) ごとに `maxDiagnosticsPerFile` 件まで保持する。上限超過分は破棄し、ファイルごとに 1 件だけ `KSWIFTK-PIPELINE-0005` の打ち切り diagnostic を発行する（破棄物に `.error` が含まれた時点で notice も `.error` に昇格し、error 喪失時に exit code が成功にならないことを保証する）。

---

# Doc J3: 文字列インターン / ID 系（全モジュール共通）

## J3.1 Interner（必須）

* **Identifier / FQName / String literal / Operator** 等をインターン。
* `String` 比較を避け、`Int32` 比較に寄せる。

```swift
public struct InternedString: Hashable, Sendable, Codable {
    public let rawValue: Int32
    public static let invalid: InternedString
}

public final class StringInterner: @unchecked Sendable {
    public func intern(_ s: String) -> InternedString
    public func resolve(_ id: InternedString) -> String
    public func snapshotValues() -> [String]
    public func preload(_ strings: [String])
}
```

## J3.2 ID の命名規約

* `TokenID`, `NodeID`, `SymbolID`, `TypeID`, `DeclID` などは `Int32`。
* “未設定” は `-1` を使用（Optional を乱用しない）。

---

# Doc J4: Lexer 詳細 API（`KotlinLexer`）

Kotlin の lexical/syntax ルールは spec と公式 grammar を基準にする。 ([Kotlin][6])
実装時の参照として Kotlin spec の ANTLR lexer 定義（KotlinLexer.g4）も利用可能（ただしコード生成はしない）。 ([GitHub][7])

## J4.1 Token モデル

現行実装は `Sources/CompilerCore/Lexer/TokenModel.swift`。

```swift
public enum TriviaPiece: Equatable {
    case spaces(Int)
    case tabs(Int)
    case newline              // 1回分
    case lineComment(String)  // "//..."
    case blockComment(String) // "/*...*/"
    case shebang(String)      // "#!..."
}

public enum TokenKind: Equatable {
    case identifier(InternedString)
    case backtickedIdentifier(InternedString)

    case keyword(Keyword)
    case softKeyword(SoftKeyword) // parser が必要に応じて解釈する

    case intLiteral(String)    // raw text (後で数値化)
    case longLiteral(String)
    case uintLiteral(String)
    case ulongLiteral(String)
    case floatLiteral(String)
    case doubleLiteral(String)
    case charLiteral(UInt32)   // unicode scalar
    case stringSegment(InternedString) // "abc" の literal 部分
    case stringQuote           // "
    case rawStringQuote        // """
    case multiDollarStringQuote(dollarCount: Int)
    case multiDollarRawStringQuote(dollarCount: Int)
    case templateExprStart     // ${
    case templateExprEnd       // }
    case templateSimpleNameStart // $name

    case symbol(Symbol)        // operators & punctuators
    case eof
    indirect case missing(expected: TokenKind)
}

public struct Token: Equatable {
    public let kind: TokenKind
    public let range: SourceRange
    public let leadingTrivia: [TriviaPiece]
    public let trailingTrivia: [TriviaPiece]
}
```

## J4.2 Keyword / SoftKeyword / Symbol（固定）

* Keyword は Kotlin の “ハードキーワード” を全部列挙する（`class`, `fun`, `val`, `var`, `object`, …, `suspend`, `inline`, `reified`, `expect`, `actual` など）。
* SoftKeyword は Kotlin の “文脈依存語” を列挙（例：`by`, `get`, `set`, `field`, `property`, `receiver`, `param`, `setparam`, `delegate`, `file`, `where`, `constructor`, `init` 等）。
  ※ lexer は `identifier` として出してもよいが、この仕様では **softKeyword を kind として区別**し、parser での分岐を簡単にする（失敗時も identifier と互換扱いにできる）。

Symbol は `+ - * / % ++ -- && || ! == != <= >= < > = += -= *= /= %= .. ..< ?: ?. !! :: , . ; : -> => ( ) [ ] { } @ #` を全列挙。

## J4.3 Lexer API

```swift
public final class KotlinLexer {
    public init(file: FileID,
                source: Data,
                interner: StringInterner,
                diagnostics: DiagnosticEngine)

    public func lexAll() -> [Token]
}
```

必須要件：

* 文字列テンプレート用の **状態機械**を実装：

  * default
  * string（`"`）
  * rawString（`"""`）
  * template（`${ ... }` で入れ子可能）

* **改行は trivia として必ず保持**（ASI に必要）。
  parser 側は statement 境界の判断で `newline` trivia を参照可能にする。

## J4.4 lexer のエラー規約（必須）

* 不正なエスケープ、閉じていないコメント/文字列、数値フォーマット不正 → `KSWIFTK-LEX-xxxx` を emit。
* 可能なら復帰して lex 継続（EOF まで）。

---

# Doc J5: Parser / CST Arena / エラー回復（`KotlinParser` + `KotlinSyntaxTree`）

公式 grammar は “latest stable & experimental 除外” が基準。 ([Kotlin][1])
spec の syntax grammar には `kotlinFile` / `script` / `semi` があるので、これを最上位として実装する。 ([Kotlin][2])

## J5.1 CST は “Arena + ID” で固定

### SyntaxArena

```swift
public struct NodeID: Hashable { public let rawValue: Int32 }
public struct TokenID: Hashable { public let rawValue: Int32 }

public enum SyntaxChild {
    case node(NodeID)
    case token(TokenID)
}

public struct SyntaxNode {
    public let kind: SyntaxKind
    public let range: SourceRange
    public let firstChildIndex: Int32
    public let childCount: Int16
}

public final class SyntaxArena {
    public private(set) var nodes: [SyntaxNode] = []
    public private(set) var children: [SyntaxChild] = []
    public private(set) var tokens: [Token] = []

    public func appendToken(_ t: Token) -> TokenID
    public func makeNode(kind: SyntaxKind, range: SourceRange, _ kids: [SyntaxChild]) -> NodeID
    public func node(_ id: NodeID) -> SyntaxNode
    public func children(of id: NodeID) -> ArraySlice<SyntaxChild>
}
```

### SyntaxKind（最低限の粒度）

* `kotlinFile`, `script`, `packageHeader`, `importList`, `importHeader`
* 宣言：`classDecl`, `objectDecl`, `interfaceDecl`, `funDecl`, `propertyDecl`, `typeAliasDecl`, `enumEntry`, …
* 文：`statement`, `block`, `loopStmt`, `tryExpr`, …
* 式：`ifExpr`, `whenExpr`, `callExpr`, `binaryExpr`, `unaryExpr`, `lambdaLiteral`, `objectLiteral`, `stringTemplate`, `callableRef`, …
* 型：`typeRef`, `nullableType`, `functionType`, `suspendFunctionType`, `typeArgs`, `typeProjection`, …

粒度は “後段の AST Builder が楽になる” 範囲で良い。**CST は lossless で token を保持できる**のが最重要。

## J5.2 Parser API（固定）

```swift
public final class KotlinParser {
    public init(tokens: [Token],
                interner: StringInterner,
                diagnostics: DiagnosticEngine)

    public func parseFile() -> (arena: SyntaxArena, root: NodeID)
}
```

### トップレベル文とスクリプト（`.kts`）

`parseFile()` はトップレベルに宣言以外の文（式文・`while` など）を見つけると、ルートを `.script` にして暗黙の `main` 本体へ束ねる。これは `kotlinc -script` と同じ `.kts` 向けの意味論であり、通常の `.kt` では不正。`ParsePhase` は `.kt`（`.kts` 以外のユーザー入力）の `.script` ルートに対し、文ごとに `KSWIFTK-PARSE-0023`（kotlinc の `expecting a top level declaration` 相当）を報告する。`fun main` の書き忘れや不完全なファイルが実行可能バイナリになることを防ぐため。`Scripts/diff_cases/script_*.kt` は diff ハーネスが `.kts` コピーを kotlinc / kswiftc の両方へ渡す。

## J5.3 TokenStream 補助

```swift
public final class TokenStream {
    public let tokens: [Token]
    public private(set) var index: Int = 0

    public func peek(_ k: Int = 0) -> Token
    public func advance() -> Token
    public func atEOF() -> Bool
    public func consumeIf(_ predicate: (Token) -> Bool) -> Token?
}
```

## J5.4 エラー回復（必須）

* “同期点” を固定：

  * トップレベル：`class/fun/val/var/object/interface/typealias/import/package`, `}`, `EOF`
  * ブロック内：`;`/改行, `}`, `catch/finally`, `else`
* 回復戦略：

  1. 期待トークン欠如 → **missing token** を仮想挿入（Node に `isMissing` フラグを持たせてもよい）
  2. 不要トークン → 破棄して進む
  3. どうにもならない → 同期点までスキップ

## J5.5 `<T>` vs `<` の曖昧性（必須）

Kotlin パース最大の地雷なので、ここは仕様で固定する：

* Parser は “型引数を読みたい文脈” でのみ `<` を type-args 開始として解釈する。
* 文脈判定関数：

  * `canStartTypeArguments(after: NodeID/Token)` を設け、
  * 次トークン列を最大 N=32 まで先読みして `>` まで整合が取れたら type-args とみなす。
* 整合条件（最低限）：

  * `<` の内側は `typeProjection (',' typeProjection)*` としてパース可能
  * `>` の直後が “呼び出し/参照に続けられるもの（`(`, `.`, `::`, `?., !!., <` etc）” である

失敗したら通常の `<` 演算子として扱う（戻す）。

---

# Doc J6: AST（`KotlinAST`）と CST→AST 変換（`BuildAST` Phase）

## J6.1 AST の目的

* CST の trivia/token 詳細は落とし、**意味解析に必要な構造**だけ残す。
* ただし **位置情報（SourceRange）**は必ず保持する。

## J6.2 AST の基本表現

* AST も “Arena + ID” で揃える（メモリ効率と参照安定）。

```swift
public struct ASTNodeID: Hashable { public let rawValue: Int32 }
public struct DeclID: Hashable { public let rawValue: Int32 }
public struct ExprID: Hashable { public let rawValue: Int32 }
public struct TypeRefID: Hashable { public let rawValue: Int32 }

public final class ASTModule {
    public let files: [ASTFile]
    public let arena: ASTArena
}

public struct ASTFile {
    public let fileID: FileID
    public let packageFQName: [InternedString]
    public let imports: [ImportDecl]
    public let topLevelDecls: [DeclID]
}
```

### BuildAST の採番契約

`DeclID` / `ExprID` / `TypeRefID` は、入力ファイルに対応する syntax tree の順序と、
各ファイル内の arena 追加順で採番する。`jobs=1/2/4` および task の完了順に依存しない。
BuildAST は各ファイルを private arena / interner で構築し、全 worker の完了後に入力順で
module arena へ統合する。ノード内の参照、annotation の元 token、付随テーブルの key/value、
file の宣言・script 参照を同時に remap し、負の invalid sentinel と SourceRange は維持する。
compound assignment の一時名は FileID と SourceRange で識別し、file-local ID を文字列へ埋め込まない。
既存の incremental arena は変更しない prefix として保持し、再コンパイルしたファイルだけを
同じ順序で末尾へ追加する。同じキャッシュ状態・再コンパイル集合なら jobs 間で ID が一致する。
clean build と incremental build の ID 一致は保証しない。

### 代表ノード（抜粋）

```swift
public enum Decl {
    case classDecl(ClassDecl)
    case funDecl(FunDecl)
    case propertyDecl(PropertyDecl)
    case typeAliasDecl(TypeAliasDecl)
    case objectDecl(ObjectDecl)
    case enumEntry(EnumEntryDecl)
    // ...
}

public struct FunDecl {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let typeParams: [TypeParamDecl]
    public let receiverType: TypeRefID?
    public let valueParams: [ValueParamDecl]
    public let returnType: TypeRefID?
    public let body: FunctionBody // block or exprBody
    public let isSuspend: Bool
    public let isInline: Bool
}
```

## J6.3 Modifiers（固定）

`Modifiers` は bitset で持つ：

* visibility: public/internal/protected/private
* modality: final/open/abstract/sealed
* classKind: data/enum/annotation/value
* fun: inline/tailrec/operator/infix/external/suspend
* param: noinline/crossinline/vararg
* expect/actual

## J6.4 AST Builder の責務

* CST を walking し、AST を生成
* この段階では **解決しない**（識別子は raw のまま）
* ただし “構文糖衣” は残してよい（desugar は KIR lowering）

### Annotation の文字列引数

`AnnotationNode.arguments` と export/import する annotation metadata は同じ canonical 表現を使う。
単一 literal は regular / raw の区切り引用符を一組だけ保持し、内容の escape や引用符を変更しない。
multi-dollar literal の `$` prefix は開き区切りだけに付く。空文字列も同じ規則で扱う。
named 引数は `name=` を保持する。literal だけの連結は従来どおり、評価結果の UTF-16 code unit を
`\uXXXX` で表す一個の regular literal に畳み込む。識別子や template を含む式は畳み込まない。

literal decoder は canonical raw の内容に含まれる引用符を保存する。旧 token 再構成の追加引用符は
raw の実際の引用符と区別できない場合があるため、旧表現の復号には明示的な representation 指定を使う。
metadata の annotation entry は `literalFormat:canonical` を保持する。マーカーがない旧 artifact の
文字列引数は decoder で旧 token 表現から canonical に変換し、通常・indexed import の双方へ渡す。
frontend snapshot version 6 より前の保存済み AST / 出力 cache は再利用せず、再生成する。

---

# Doc J7: シンボル・スコープ・解決（`KotlinSemantics`）

Kotlin/Core の仕様範囲（式・宣言・型・オーバーロード解決）をここで実装する。 ([Kotlin][2])

## J7.1 SymbolID と Symbol

```swift
public struct SymbolID: Hashable { public let rawValue: Int32 }

public enum SymbolKind {
    case package, `class`, `interface`, object, enumClass, annotationClass
    case typeAlias
    case function
    case constructor
    case property
    case field
    case typeParameter
    case valueParameter
    case local
    case label
}

public struct Symbol {
    public let id: SymbolID
    public let kind: SymbolKind
    public let name: InternedString
    public let fqName: [InternedString]   // package + nested
    public let declSite: SourceRange?
    public let visibility: Visibility
    public let flags: SymbolFlags
}
```

## J7.2 Scope（固定）

```swift
public protocol Scope {
    var parent: Scope? { get }
    func lookup(_ name: InternedString) -> [SymbolID]
    func insert(_ sym: SymbolID)
}
```

実装：

* `FileScope`, `PackageScope`, `ImportScope`, `ClassMemberScope`, `FunctionScope`, `BlockScope`

lookup 優先順位（固定）：

1. ローカル（block → function → class）
2. 明示 import
3. ワイルドカード import
4. デフォルト import（stdlib）

## J7.3 2パス（必須）

* Pass A: “ヘッダ収集”

  * クラス名、型パラメータ、関数シグネチャ、プロパティ型（明示があれば）
  * 相互再帰を許すため、body はまだ見ない
* Pass B: “本体解析”

  * 初期化子、関数 body、getter/setter、init ブロック

## J7.4 Sema の出力（SemaModule）

```swift
public final class SemaModule {
    public let symbols: SymbolTable
    public let types: TypeSystem
    public let bindings: BindingTable // AST node -> Symbol/Type
    public let diagnostics: DiagnosticEngine
}
```

`BindingTable` は最低限：

* `ExprID -> TypeID`
* `IdentifierExpr -> SymbolID`
* `CallExpr -> CalleeSymbolID + chosen overload`
* `DeclID -> SymbolID`

## J7.5 Stored property initialization (KUU-2142)

After receiver and constructor delegation binding, `ValPropertyInitializationChecker`
tracks possible initialization with union and definite initialization with intersection.
Possible writes retain the immutable-property reassignment check (SEMA-0014).
Each primary/secondary constructor and object initialization must definitely initialize
all deferred stored `val`/`var` properties; otherwise the declaration receives SEMA-0424.
A bare constructor return is a normal exit, and `this(...)` delegation consumes the
chosen constructor's summary after ordered property initializers and init blocks.
Constructor bodies may initialize properties declared later in the source text;
init blocks still cannot initialize a property before its declaration.
Kotlin also rejects a deferred property in a constructor with no normal exit.

Declaration initializers, delegates, explicit backing-field initializers, primary
property parameters, abstract/lateinit/expect properties, and fieldless custom
accessors do not require deferred initialization. Concrete stored properties in an
abstract class still do. Fieldless mutable properties require both custom accessors
and no bound backing-field use. A custom setter call does not prove initialization;
only a direct write to this instance with the default setter counts. Deferred lambda
and local-function writes, and writes to another receiver, do not initialize this
instance. FIELD annotations do not alter this analysis.

---

# Doc J8: 型システムと TypeID（`TypeSystem`）

## J8.1 TypeID と型表現

```swift
public struct TypeID: Hashable { public let rawValue: Int32 }

public enum Nullability { case nonNull, nullable, platformType }

public enum TypeKind {
    case error
    case unit
    case nullableUnit // Unit? carries a value or the null sentinel
    case platformUnit // Unit! retains flexible bounds Unit..Unit?
    case nothing
    case any(Nullability)

    case primitive(PrimitiveType, Nullability) // nullable primitive は原則 box へ lowering
    case classType(ClassType)
    case typeParam(TypeParamType)
    case functionType(FunctionType)
    case intersection([TypeID])
    case kClassType(KClassType)
}

public struct ClassType {
    public let classSymbol: SymbolID
    public let args: [TypeArg]
    public let nullability: Nullability
}

public enum TypeArg {
    case invariant(TypeID)
    case out(TypeID)
    case `in`(TypeID)
    case star
}

public struct FunctionType {
    public let receiver: TypeID?
    public let params: [TypeID]
    public let returnType: TypeID
    public let isSuspend: Bool
    public let nullability: Nullability
}
```

`KClassType` は不変の `KClass<T : Any>` を表す。`out` / `in` / `*` の use-site projection は nominal `ClassType` の `TypeArg` に保持し、固定 receiver との適合判定やメタデータ保存で不変型へ消去しない。KClass 型の共通型は、入力型がすべての入力の上位型ならその型を保持し、それ以外では `KClass<out U>` に近似して `KClass<U>` の不変性を維持する。

generic extension の `KClass<T>` receiver は不変の制約として分解し、projection から推論する
`T` は `TypeParamType.capture` に呼び出し内の identity と下限・上限を持つ。
`KClass<in Int>` の capture は `Int <: capture <: Any` であり、`Int` を消費できるが
戻り値を `Int` に固定しない。上限のメンバーと builtin 演算は読み取り上限を使い、
capture を含むプロパティへの代入は下限を含む subtype 制約を検査する。
metadata の公開型シグネチャは capture identity を外へ出さず、読み取り上限と
安全な use-site projection に近似し、反変位置と nullable を保持する。
class literal の reflection target は nominal symbol を保持し、builtin の `KClass` 型引数は
通常の値型と同じ canonical `TypeID` を使う。

## J8.2 TypeSystem API

```swift
public final class TypeSystem {
    public func make(_ kind: TypeKind) -> TypeID
    public func kind(of id: TypeID) -> TypeKind

    public func isSubtype(_ a: TypeID, _ b: TypeID) -> Bool
    public func lub(_ types: [TypeID]) -> TypeID
    public func glb(_ types: [TypeID]) -> TypeID
}
```

必須：

* `Nothing` はすべての型の subtype
* nullable/non-null の規則
* 関数型の variance（パラメータ反変、戻り共変）
* 型引数 variance（declaration-site + use-site を合成）

---

# Doc J9: 型推論（制約）・オーバーロード解決（`ConstraintSolver` + `OverloadResolver`）

## J9.1 制約変数（TypeVar）

```swift
public struct TypeVarID: Hashable { public let rawValue: Int32 }

public enum ConstraintKind { case subtype, equal, supertype }

public struct Constraint {
    public let kind: ConstraintKind
    public let left: TypeID
    public let right: TypeID
    public let blameRange: SourceRange?
}
```

## J9.2 推論プロトコル

* 式ごとに “期待型 expectedType” を受け取り推論する（Kotlin のローカル推論に寄せる）。
* `CallExpr` は：

  1. 候補関数群を収集
  2. それぞれに type vars を割り当て
  3. 引数から制約生成
  4. solve
  5. 最良候補選択（tie は曖昧エラー）

## J9.3 API（固定）

```swift
public final class ConstraintSolver {
    public func solve(vars: [TypeVarID],
                      constraints: [Constraint],
                      typeSystem: TypeSystem) -> Solution
}

public struct Solution {
    public let substitution: [TypeVarID: TypeID]
    public let isSuccess: Bool
    public let failure: Diagnostic?
}
```

## J9.4 オーバーロード解決（固定）

```swift
public final class OverloadResolver {
    public func resolveCall(candidates: [SymbolID],
                            call: CallExpr,
                            expectedType: TypeID?,
                            ctx: SemaContext) -> ResolvedCall
}
```

`ResolvedCall` は以下を含む：

* chosen callee symbol
* substituted type arguments（推論結果）
* parameter mapping（名前引数・デフォルト引数・vararg 展開結果）

---

# Doc J10: Data-flow / Smart cast / when exhaustiveness（Kotlin 2.3 の要点）

Kotlin 2.3 で when の exhaustiveness が data-flow ベースで強化されているので、ここを必ず実装対象に含める。 ([Kotlin][5])

## J10.1 DFA 状態モデル（固定）

* 各ローカル変数/プロパティ参照に対し：

  * `possibleTypes: Set<TypeID>`
  * `nullability: Nullability`
  * `isStable: Bool`（stable smart cast できるか）
* 条件式を解析して “true 分岐/false 分岐” の状態を分岐生成。

## J10.2 when exhaustiveness（必須）

* sealed class / enum / Boolean / nullable の exhaustiveness を判定し、
* expression として使われる when が non-exhaustive なら診断（error or warning は Kotlin に合わせる：差分テストで確定）。

---

# Doc J11: KIR（型付き IR）と Pass API（`KotlinIR`）

## J11.1 KIR の基本

* AST + Sema を受けて “型が付いた IR” を生成。
* KIR は lowering の対象なので、構文糖衣を残してよいが、**名前解決と型**は確定していること。

## J11.2 KIR Arena

AST と同様に ID/arena で固定。

```swift
public struct KIRDeclID: Hashable { public let rawValue: Int32 }
public struct KIRExprID: Hashable { public let rawValue: Int32 }
public struct KIRTypeID: Hashable { public let rawValue: Int32 } // 実体は TypeID 参照でも可

public final class KIRModule {
    public let files: [KIRFile]
    public let arena: KIRArena
}

public protocol KIRPass {
    static var name: String { get }
    func run(module: KIRModule, ctx: KIRContext) throws
}
```

## J11.3 例外モデル（固定：明示チャネル）

* unwind は使わない。
* すべての “throw 可能” 呼び出しは `outThrown`（runtime の `KThrowable*`）を持つ ABI へ lowering（後述 Doc J13/J15）。

---

# Doc J12: Lowering 仕様（Kotlin → 実行可能形への機械変換）

## J12.1 パス順（固定）

パス一覧と実行順序は `Sources/CompilerCore/Lowering/LoweringPhase.swift` の `passes` 配列を単一の正とする。
現行の一覧・順序依存の注記は [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) の「Lowering パス実行順序」を参照（本書では二重管理しない）。

## J12.2 各 lowering の “入力/出力条件”

例：OperatorLowering

* 入力：`binaryExpr(op:"+")`
* 出力：`call(receiver.plus(arg))` または `call(plus(receiver,arg))`（拡張候補含む）
* 条件：候補解決は sema 済みなので、ここでは chosen symbol に対して call へ落とすだけ

ForLowering

* `for (x in y) body`
* `val it = y.iterator(); while(it.hasNext()) { val x = it.next(); body }`

InlineLowering

* inline 関数の body を call site に複製
* `reified` は runtime type token を hidden arg として渡す（Doc J16）
* 関数型引数によって自動 inline 化された非 inline 宣言が、明示 inline wrapper を含む inline call cycle に到達する場合、展開前に通常の emitted body を保持して再帰呼び出しを残す。明示 inline 宣言・imported inline body・非局所 return を持つ lambda は復帰対象にせず、既存の mandatory expansion と INL-0001 診断を維持する。

---

# Doc J13: Name Mangling / ABI（Swift runtime との結合仕様）

この仕様書は “独自 backend” なので、JetBrains の mangling 互換は要求しない。**ただし安定で衝突しない** mangling を規定する。

## J13.1 シンボル名 mangling（固定）

### 基本形式

```
_KK_<module>__<fqname>__<declkind>__<signature>__<hash>
```

* `<module>`: moduleName
* `<fqname>`: package + nested class 名を `_` で連結（各要素は length-prefix でエスケープ）
* `<declkind>`: F(unction)/C(lass)/P(roperty)/K(onstructor)/G(et)/S(et)…
* `<signature>`: erased signature（型引数は `T`、nullable は `Q` など符号化）
* `<hash>`: 8桁 hex（FNV-1a 32bit）

### 型符号化（例）

* `Int` -> `I`
* `Long` -> `J`
* `Boolean` -> `Z`
* `String` -> `Lkotlin_String;`
* `T?` -> `Q<T>`
* `.kklib` の型 signature は Java 境界の `T!` を `P<T>` として保存・復元する。link-name mangling は従来どおり `Q<T>` に消去する。
* bundled `java.util.LinkedList.peekLast` は Kotlin 実装の `E?` 宣言を保ち、呼び出し signature に限って `E!` を公開する。ユーザーが同じ FQ name で宣言した Kotlin 関数には適用しない。`E!` を nullable 型引数で置換した場合は nullable を保持する（`LinkedList<Int?>.peekLast(): Int?`）。通常の Kotlin `T? → T` は許可しない。platform 値を具体的な非 nullable 型または非 nullable 上限を持つ型変数へ渡す際は KIR の `nullAssert` を挿入し、null なら NPE を投げる。上限なしの `T` への戻り値には挿入しない。具体型 `Unit!` は独立した `platformUnit` として `Unit` / `Unit?` の flexible 境界を保持する。Kotlin/JVM に合わせ、`Unit` ローカル代入は Java の値（null を含む）を保持し、`Unit` 戻り値は式を評価して singleton に変換し、非 nullable 関数引数は null 検査する。getter の参照 ABI は値を保持し、非 nullable `Unit` property の読み出しは singleton を生成する（safe call の null receiver 分岐は null を保持）。通常の `Unit? → Unit` は引き続き拒否する。
* `print` / `println` に platform String を渡す場合は nullable `Any?` overload を選び、空 `peekLast` の null をそのまま表示する。
* `Function2<A,B,R>` -> `F2<A,B,R>`
* `suspend` 関数型 -> `SF…`

## J13.2 クラスレイアウト（固定）

* heap object header:

  * `typeInfo*`
  * `flags`
  * `size`
* フィールドは 8 byte alignment。
* vtable slot は “継承順 + override で同 slot” の規則で割り当てる。
* interface dispatch は itable（interface ごとに method table）で実装。

## J13.3 例外チャネル ABI（固定）

最終的に lowering された関数 ABI：

* 戻りあり：`(args..., outThrown: *KThrowable?) -> Ret`
* 戻りなし：`(args..., outThrown: *KThrowable?) -> Void`

call site は：

* outThrown != nil なら “例外経路” へ分岐。
* try/catch は “例外値をローカルに束縛して分岐” で実装（unwind 不要）。

---

# Doc J14: Library 形式（`.kklib`）と separate compilation（macOS 専用）

“フル Kotlin” を現実的に使うには別モジュール import が必要なので、配布形式を固定する。

## J14.1 `.kklib` は “ディレクトリ” で固定（最初は zip 不要）

```
Foo.kklib/
  manifest.json
  metadata.bin
  objects/
    Foo_0.o
    Foo_1.o
  inline-kir/
    <mangled>.kirbin
  resources/ (optional)
```

## J14.2 `manifest.json`（固定スキーマ）

```json
{
  "formatVersion": 2,
  "moduleName": "Foo",
  "kotlinLanguageVersion": "2.4.20",
  "compilerVersion": "0.1.0",
  "target": "arm64-apple-macosx",
  "objects": ["objects/Foo_0.o"],
  "metadata": "metadata.bin",
  "inlineKIRDir": "inline-kir"
}
```

`--stdlib-only --emit library` artifacts add the following required fields:

```json
{
  "libraryKind": "stdlib",
  "stdlibManifestHash": "<hash>"
}
```

The stdlib artifact's `target`, metadata file, object list, and inline-KIR
directory are validated before import. A missing or mismatched field is a
hard error; the compiler does not fall back to injecting bundled sources.

## J14.3 `metadata.bin`（最小要件）

* public API の “ヘッダ情報” を入れる（型・シグネチャ・vtable slot・field offsets）
* inline 関数は body を `inline-kir/` に保存し、import 側がインライン展開できるようにする。
* inline `reified` 関数では、呼び出し側が hidden type-token 引数を追加するため、metadata に reified 型パラメータのインデックス（`reified=...`）も含める。

新規 `.kklib` は manifest `formatVersion=2` と binary indexed metadata v3 を出力する。
reader は manifest 1 と legacy v1 / text indexed v2 も引き続き受け付ける。
旧 reader は manifest 2 を拒否するため、binary index を legacy text と誤認しない。

v3 の byte layout（全整数は little-endian、alignment 非依存）:

* magic: ASCII `kklib-metadata-v3\n`
* header: UInt32 の record count / string count / string-section byte length / entry width（80）
* string section: string ID 順に UInt32 UTF-8 byte length + UTF-8 bytes。ID 0 は空文字列で、optional field では nil を表す。
* entry table: record ごとに UInt64 body offset / length、UInt32 arity / flags / kind ID / visibility ID、12 個の UInt32 string ID。
* body: 従来の record text を UTF-8 で連結。offset / length は body の先頭を基準とする。

string field 順序は fqName / mangledName / receiverOwnerFQName / defaultStubExternalLinkName /
externalLinkName / propertyReceiverTypeSignature / propertyGetterExternalLinkName /
nominalTypeParametersSignature / companionObjectFQName / objectInitializerLinkName /
companionInitializerLinkName / enumStaticInitLinkName。
kind ID は package / class / interface / object / enumClass / annotationClass / typeAlias /
function / constructor / property / field / backingField / typeParameter / valueParameter /
local / label の順（0..15）、visibility ID は public / private / internal / protected（0..3）。
flags bit 0..15 は suspend / inline / operator / infix / override / memberExtension /
mutable / dataClass / openClass / innerClass / sealedClass / funInterface / valueClass /
expect / actual / completeInitializerInfo。bit 16..17 は modality（0=final, 1=open, 2=abstract）。bit 18..20 は setter visibility
（0=未指定, 1=public, 2=private, 3=internal, 4=protected）。
未知の flag、ID、entry width、範囲外の body slice、不正な string UTF-8 は読み込み時に拒否する。
本文の UTF-8 / signature / layout / annotation は宣言への semantic query 時にだけ decode する。

index は shell 登録に必要な shape 専用型を使い、全件の汎用 MetadataRecord を生成しない。
名前による検索は登録済み SymbolTable に任せ、wire index に重複した name hash は持たせない。
共有 string ID によって routing 用の文字列を再利用する。cache integrity check も本文を decode せず、
index の inline flag / mangledName から必要な inline-KIR blob の存在を検証する。

通常のライブラリを bundled stdlib ソースでコンパイルする場合、stdlib 本体も
KIR・オブジェクトへ出力する。stdlib 宣言はライブラリの公開メタデータから除外し、
bundled 関数には既存の `linkonce_odr` を適用する。プリコンパイル済み stdlib を
指定した場合は、import 済みのリンク名でその artifact を参照する。
そのライブラリの consumer にも、同じ stdlib artifact を依存先として指定する。

**注意**：この方式は Kotlin の inline / reified を跨モジュールで成立させるために必須。

## J14.4 Kotlin/Native `.klib` の消費（実験的）

`-I` のサーチパス上にある Kotlin/Native 形式 `.klib`（packed ZIP / unpacked ディレクトリ）も import・実行できる。`.kklib` とは別フォーマットで、protobuf 直列化された Kotlin IR を直接読み、`SymbolTable`/`TypeSystem`/`KIR` にマテリアライズする（パイプライン詳細は `docs/ARCHITECTURE.md` §13.1）。

* 対象: `abi_version` 2.3.x（2.4.x は best-effort、`KSWIFTK-LIB-0027`）
* manifest `depends` は検証され依存順でモジュール初期化が走る（欠落は `KSWIFTK-LIB-0030` 警告）
* `.klib` はコンパイル済みオブジェクトを持たないため、body すべてが consumer 側の KIR に翻訳されて実行される。未対応 IR 形式は `KSWIFTK-LIB-0029` 警告 + abort
* 制約: default 引数の `$default` stub 経由呼び出し、expect/actual、インラインの再 materialization は未対応

---

# Doc J15: LLVM Backend 実装境界（`CompilerBackend`）

## J15.1 依存と目標

* Swift から LLVM C API を呼ぶ（modulemap + SwiftPM）。
* 出力：object（.o）または LLVM IR（.ll）。executable の macOS 通常リンクは `swiftc -###` で取得した単一 clang ジョブを直接実行する。引数は `.runtime-build/link-plans/` に保存し、ターゲット・ドライバ・Xcode 選択・SDK・互換ライブラリの指紋で再検証する。初回はドライバ照会が必要。debug（dSYM 生成を含む）・Linux・未対応のドライバ出力・キャッシュ取得失敗では `swiftc` を呼ぶ。
* Runtime object 探索はリンクごとにパッケージ検証とソース指紋の計算を一度行い、同じ結果から scratch/manifest/build パスを組み立てる。完了 manifest・object の存在検証・ビルドロックは維持する。
* `LLVMBackend` は `CompilerBackend` target 内部型であり、`CompilerCore` の public API にはしない。

## J15.2 Backend の主要型

現行実装は `Sources/CompilerBackend/LLVMBackend.swift`、phase 接続は `Sources/CompilerBackend/CodegenPhase.swift` / `Sources/CompilerBackend/LinkPhase.swift`。

```swift
final class LLVMBackend {
    init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        debugInfo: Bool,
        diagnostics: DiagnosticEngine
    ) throws

    func emitObject(
        module: KIRModule,
        outputObjectPath: String,
        interner: StringInterner,
        sourceManager: SourceManager?,
        fileFacadeNamesByFileID: [Int32: String],
        reflectionMetadataRecords: [MetadataRecord],
        reflectionMetadataSymbolPrefix: String?,
        linkOnceODRSymbols: Set<SymbolID>
    ) throws

    func emitLLVMIR(
        module: KIRModule,
        outputIRPath: String,
        interner: StringInterner,
        sourceManager: SourceManager?,
        fileFacadeNamesByFileID: [Int32: String],
        reflectionMetadataRecords: [MetadataRecord],
        reflectionMetadataSymbolPrefix: String?
    ) throws
}
```

`RuntimeLinkInfo` 型は存在しない。link に必要な library/search path は `CompilerOptions` が保持し、runtime object discovery と executable link は `LinkPhase` が担当する。

`LinkPhase` が生成するエントリラッパ（`LLVMEntryPointObjectEmitter`）の終了ステータス規約: 正常終了は常に `0`、未捕捉例外は `1`（`KSWIFTK-LINK-0003` を stderr に出力）。`main` 自身の戻り値は終了ステータスに使わない — Kotlin で非ゼロを返す手段は `kotlin.system.exitProcess` だけであり、これは `__kk_system_exitProcess`（`Never`）としてプロセスを直接終了させるためラッパを通らない。なお kotlinc は戻り値型が `Unit` でない `main` をエントリポイントと認めない（`Main-Class` なしの jar を出す）が、kswiftc はこれを受理して値を捨てる: `runBlocking` / `coroutineScope` / `Deferred.await` を `Any` 返しとしてモデル化している都合上、`fun main() = runBlocking { ... }` は本体に関わらず非 `Unit` になるため、拒否すると正当なコードが通らなくなる。

## J15.3 文字列・配列・例外・コルーチンの呼び出し境界

backend は “言語コア操作” を runtime 関数呼び出しに落とす：

* string concat
* array bounds check
* throwing propagation
* coroutine resume/suspend

つまり backend は “KIR の lowering 結果 + runtime ABI” だけを信じてコード生成する。

---

# Doc J16: Runtime（Swift 実装）C ABI 仕様（`Runtime` + `StdlibCore`）

Kotlin/Native も tracing GC を備えた自動メモリ管理を採用している（参考）。 ([Kotlin][8])
この仕様書でも **non-moving tracing GC（mark-sweep）**を固定採用する。

## J16.1 ランタイムの公開シンボル（`@_cdecl`）

### メモリ

```swift
@_cdecl("kk_alloc")
public func kk_alloc(_ size: UInt32, _ typeInfo: UnsafePointer<KTypeInfo>) -> UnsafeMutableRawPointer

@_cdecl("kk_gc_collect")
public func kk_gc_collect()
```

### 型情報

```swift
public struct KTypeInfo {
    public let fqName: UnsafePointer<CChar>
    public let instanceSize: UInt32
    public let fieldCount: UInt32
    public let fieldOffsets: UnsafePointer<UInt32>
    public let vtableSize: UInt32
    public let vtable: UnsafePointer<UnsafeRawPointer>
    public let itable: UnsafeRawPointer?
    public let gcDescriptor: UnsafeRawPointer?
}
```

### 例外

```swift
@_cdecl("__kk_throwable_new")
public func __kk_throwable_new(_ message: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer
```

### 文字列

```swift
@_cdecl("kk_string_from_utf8")
public func kk_string_from_utf8(_ ptr: UnsafePointer<UInt8>, _ len: Int32) -> UnsafeMutableRawPointer

@_cdecl("kk_string_concat")
public func kk_string_concat(_ a: UnsafeMutableRawPointer?, _ b: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer
```

### println

```swift
@_cdecl("kk_println_any")
public func kk_println_any(_ obj: UnsafeMutableRawPointer?)
```

## J16.2 GC（必須仕様）

* stop-the-world mark-sweep（non-moving）
* root set:

  * globals（singleton/object/companion）
  * thread stacks：**Kotlin フレームマップ**により列挙
  * coroutines：Continuation オブジェクトから辿れる参照も root 扱い
* 各関数は compile 時に “GC root map” を生成し、runtime に登録する（例：`kk_register_frame_map(functionId, mapPtr)`）（現状は未配線。ARCH-014 で emit 停止）

## J16.3 オブジェクト header（固定）

```c
struct KKObjHeader {
  KTypeInfo* typeInfo;
  uint32_t flags;
  uint32_t size;
};
```

---

# Doc J17: Coroutines（コンパイラ変換 + Runtime）最終仕様

coroutines の spec 要点：suspend 関数は CPS 変換され、`Continuation<T>` が追加引数、戻りが `Any?` になり “suspend したら特殊値” を返す。 ([Kotlin][3])

## J17.1 Runtime の coroutine コア

### Continuation

```swift
public protocol KKContinuation {
    var context: UnsafeMutableRawPointer? { get } // CoroutineContext object
    func resumeWith(_ result: UnsafeMutableRawPointer?) // Result<T> object
}
```

### COROUTINE_SUSPENDED

```swift
@_cdecl("kk_coroutine_suspended")
public func kk_coroutine_suspended() -> UnsafeMutableRawPointer
```

* これは singleton のアドレスを返す。
* codegen は `ret == kk_coroutine_suspended()` で比較する。

## J17.2 `suspend fun` の lowering（固定アルゴリズム）

Sema は overload 解決とラムダ型推論の完了後、suspend 関数・suspend 関数値の呼び出し文脈を検査する。非 suspend 文脈からの呼び出しは `KSWIFTK-SEMA-0307` で拒否する。suspend 関数・suspend ラムダは呼び出しを許可し、通常のラムダは inline 引数（noinline / crossinline を除く）の場合だけ外側の文脈を継承する。名前付き関数、デフォルト引数、クラス・object の初期化処理はそれぞれ独立した文脈を持つ。関数参照の取得自体は suspension point ではない。

関数参照を変数に保存した `val r = ::add; r.invoke(3, 4)` は、元の structural function type で引数・戻り値を検査し、通常の `r(3, 4)` と同じ callable-value 経路へ束縛する（KUU-1723）。反射メンバーや extension の解決用に作る `KFunction<R>` lookup view は `.invoke` の署名を置き換えない。束縛 receiver は参照に保持し、非束縛 receiver は第一引数として受け取る。safe-call は nullable receiver を unwrap して nullable の結果を返し、unsafe nullable 呼び出し、不正な引数数・型・named/spread 引数は従来どおり拒否する。通常の nominal `operator fun invoke` は member dispatch を維持する。

直接指定した関数参照は、期待される関数型に合わせて default 引数省略、vararg 展開、Unit 戻り値化、non-suspend から suspend への変換を adapter に記録する。`val f: suspend (Int) -> Int = ::identity` も adapter を実体化し、変換済み参照は `KFunction` として扱わない。既に変数へ保存した通常の関数値を suspend 型へ代入することは subtype 関係にせず拒否する。

`receiver.(expression)(args)` は括弧内 expression を callee とする明示 receiver の receiver-function-value invocation として解決する。callee expression を先に評価し、receiver、明示引数の順に一度ずつ評価してから関数本体を実行する。通常の function type の第一引数を receiver として流用せず、receiver 型・引数型・arity が function type と合わない呼び出しは拒否する。

自動インライン化で native entry point を出力しない HOF と、別ライブラリから読み込んだ inline 関数への参照は、実体を持つ callable-reference wrapper を作る。その wrapper 内の呼び出しを InlineLowering で展開し、存在しない関数アドレスへのリンクを避ける。indexed import は inline body の遅延読込前に symbol flags で判定し、receiver function type の receiver は第一引数として渡す。通常の参照は型付き capture・Kotlin signature・例外経路・reflection を保持し、collection HOF の callback だけが既存の closureRaw ABI を使う。source の後方宣言への参照も、宣言と同じ自動インライン化方針で判定する。reified 関数参照は contextual solver が推論した型引数を通常の call binding とは別に宣言順で保存する。外側の lexical 型パラメータは rigid な型として扱い、周囲の generic call の未確定な direct return leaf だけを延期できる。既知の入力、arity、suspend、nullability と bounds は検査する。既知の call-result 型は lambda と参照で共有するが、宣言の bound より広い期待型で戻り型を固定しない。延期した `R?` では `R` の bound を nullable にして検査する。延期を用いた適合判定は reified / nonreified 候補で同じにする。bound receiver の nullable 型は lookup view とは独立して推論 evidence に保持する。参照の型付き thunk は通常の capture・hidden token capture・論理引数を受け取り、参照先には通常の capture・論理引数・宣言順の reified token を渡す。トークンは escaping lambda / local nominal / object の環境にも保存し、nullable flag の計算は通常の reified call と共有する。SAM はこの thunk を包み、collection HOF は既存 adapter で環境を decode する。reflection の名前・flags・論理 parameter metadata は元の参照先を記述し、reified 関数の反射 `.call` は登録済み metadata の invoker=0 を通じて `UnsupportedOperationException` になる。通常の関数値 invoke は型付き thunk を実行し、例外経路を維持する。

### 入力

KIR で `isSuspend = true` の関数。

### 出力（2つ生成）

1. continuation クラス `F$Cont`（spill slots + label + completion）
2. 実体関数 `F$arity(args..., cont, outThrown)`（CPS + state machine）

### 状態機械の生成手順（固定）

1. 関数 body を CFG 化（基本ブロック列）
2. suspension point を列挙
   suspension point = “suspend 関数呼び出し” または “suspend lambda invoke”
3. 各 suspension point に `label` を割り当て（0..N）
4. spill が必要なローカルを解析：

   * そのローカルが “suspension を跨いで live” なら spill
5. `F$Cont` に spill fields を生成
6. 本体を以下のテンプレで出力：

   * `switch (cont.label)`:

     * `case 0:` 初期
     * `case k:` 各再開地点
   * 各 suspension 前：

     * spill 保存
     * `cont.label = next`
     * call suspend callee
     * if returned suspended -> return suspended
     * else result をローカルに入れて継続

`Mutex.lock()` / `lock(owner)` は runtime suspend point として扱い、KIR の末尾の
zero continuation を呼出元の continuation で置換する。owner 版の `outThrown` は
独立した例外チャネルとして維持する。競合待機は cancellable continuation で通知し、
所有権の移譲後でも delivery 前に取消された場合は mutex を返却する。同期取得と
成功 delivery 後には汎用の取消検査を追加しない。continuation が zero の
非 suspend 呼出しは引き続き blocking waiter を使う（KUU-2139）。
ソース由来の `EmptyCoroutineContext` は空 context と解決し、既定の
`runBlocking` と子 coroutine が同じ event loop を継承する。

## J17.3 non-suspend からの起動（KxMini）

* `runBlocking`, `launch`, `async`, `delay` を Swift runtime 側で提供（GCD）。
* `delay` は `DispatchSourceTimer` で resume。

---

# Doc J18: テストハーネス（“仕様の穴” を埋める最重要装置）

## J18.1 基本方針

* 曖昧な挙動（診断の文言/順序など）は、この仕様書で決め打ちしない。
  代わりに **参照 `kotlinc 2.4.20` と差分テスト**して一致させ、仕様を固める。

## J18.2 テスト種類（最低ライン）

* Lexer golden（token kind + range）
* Parser golden（CST dump の正規化）
* Sema golden（型注釈付き AST dump）
* 実行テスト（stdout/exit code）
* Coroutine テスト（delay/launch/async/例外伝播）

## J18.3 “差分テスト” の固定手順

1. 入力 `.kt` を kotlinc（JVM）で実行し stdout を保存
2. 同じ入力を `kswiftc` で実行し stdout を保存
3. 正規化（改行差、スタックトレース差など）して比較
4. 不一致が出たら：

   * bug としてチケット化
   * どの Phase のどの規約に違反したかを特定

---

# Doc J19: Coverage Hygiene（SwiftPM）

## J19.1 目的

* `CompilerCore` の優先8ファイルに対して、行カバレッジを継続的に監視する。
* 2026-07-02 時点では専用の tracked gate script は存在しない。未追跡の coverage script や環境変数を前提にしない。

## J19.2 実行コマンド

```bash
swift test --enable-code-coverage
swift test --show-codecov-path
```

## J19.3 判定ルール

* 優先監視対象:
  * `Sources/CompilerCore/Lexer/TokenStream.swift`
  * `Sources/CompilerCore/Driver/SourceManager.swift`
  * `Sources/CompilerCore/Sema/Resolution/ConstraintSolver.swift`
  * `Sources/CompilerCore/Sema/Resolution/OverloadResolver.swift`
  * `Sources/CompilerCore/Parser/SyntaxArena.swift`
  * `Sources/CompilerCore/Sema/Models/CompilerTypes.swift`
  * `Sources/CompilerCore/Lexer/TokenModel.swift`
  * `Sources/CompilerCore/AST/ASTModels.swift`
* しきい値を CI gate 化する場合は、`--show-codecov-path` が出力する JSON を parse する tracked script を追加してから、この節へ script 名と環境変数を戻す。

### Annotation construction metadata (KUU-1753)

`AnnotationNode.constructionTokens` preserves constructor tokens (including aliases,
escaped strings, array literals, named arguments and defaults) through frontend
snapshots. `IncrementalFrontendState.supportedVersion = 7` rejects older snapshots
and preserves prefix annotations on their operand expression IDs. Expression
annotations retain the operand's type/control flow, validate the EXPRESSION
target (or FUNCTION for function literals), and scope diagnostic suppression
to that operand. CST declaration-boundary lookahead keeps complete expression
annotation prefixes across newlines after `=` and before the operand, within the
shared 4096-token lookahead budget. An unclosed argument list recovers at the
following named declaration with a missing `)` that AST token scans honor.
Suppression names decode regular literal escapes and preserve raw literal contents.
Concatenated names remain unsuppressed, matching Kotlin 2.3.10's literal-only lookup.
After headers, annotation construction is resolved in the declaration's lexical
scope. After all declaration bodies are bound, all retention kinds require constant arguments/defaults; only RUNTIME
records receive a private producer-owned constructor factory. Constant primitive
and String expressions share `ConstPropertyEvaluator`/`ConstantCollector` rules.

Metadata records optionally store the factory's actual backend `factoryLinkName`.
Missing fields decode as legacy records. A consumer registers a symbol reference
with the normal zero-argument function-value ABI (`outThrown`); it does not rebuild
private producer constructors. Typed class/callable reads invoke factories outside
registry locks and root intermediate results until the returned list owns them.
The `KAnnotatedElement.annotations` interface fast path uses those same throwing
typed bridges for native KClass and callable handles. Source implementations
continue to dispatch through their interface getter.
Matching factory/legacy records share one occurrence; differing repeatable values
remain separate. Old read entry points retain their serialized record boxes.
`findAnnotation<T>()` returns `T?`, checks the Annotation bound, and can infer T
from the expected result type. Typed lookup uses the runtime type token (including hidden reified tokens), so
Annotation-bound searches and inferred upper result types use ordinary instance
checks without simple-name collisions. Annotation construction retains lexical
visibility while excluding inline-body call visibility rules.
Earlier application validators record checked marker IDs per annotation occurrence.
Only matching markers on that occurrence's outer constructor reuse those checks;
unvalidated markers, constructor-specific markers and nested expressions retain
normal opt-in validation.
Nested annotation declarations collect the same synthetic `equals`, `hashCode`
and `toString` members as top-level annotations. A type-qualified nested
annotation constructor has no enclosing-instance receiver.
Synthetic annotation methods and their signature parameters survive library
metadata filtering just like data-class members, preserving vtable slots and
producer link names. Existing hidden-owner and excluded-source filters remain
in effect.

### Serialization source annotations (KUU-1752)

The bundled `kotlinx.serialization` source exposes the upstream 1.10.0
`SerialName(value: String)`, `SerialInfo` and `InheritableSerialInfo` annotation
classes. Targets, public visibility, `MustBeDocumented` and retention follow the
pinned source. `SerialName` uses default RUNTIME retention; the two experimental
meta-annotations use BINARY retention. Constructors create ordinary typed
annotation objects, including value access and annotation equality/hash.

Opt-in propagates from a direct `RequiresOptIn` marker on an API, with constructor
owner and referenced types checked normally. An experimental annotation consumes
its marker at the annotation application site; that marker does not propagate
a second time to callers of declarations annotated with it. This rule applies
without special annotation-name exceptions and survives producer metadata.

Top-level typealias declarations check opt-in requirements on their expanded
underlying type. Resolved unqualified typealias constructor calls inherit the
alias's directly applied markers instead of the expanded class's markers,
while retaining the constructor's own markers. Explicit signature types still
check the expanded class, even when the
alias declaration opted in (KUU-2064; Kotlin 2.3.10).

Property uses collect opt-in requirements from the declared property and its type,
including nested type arguments and the extension receiver. Callable uses also
collect requirements from return, receiver and parameter types. Consent on the
producer permits its declaration and body; it does not remove requirements from
these API types in consumers. Direct and type-derived occurrences of the same
marker produce one diagnostic per usage, retaining each marker's severity.
Signature-derived requirements are read from the current signature rather than
cached with annotations, so inferred return types and imported metadata use the
same checks (KUU-2143; Kotlin 2.3.10). Only explicit return types receive the
function-header type check: an inferred type is checked at body usage sites,
including after speculative inference is retried.

For a synthesized primary-constructor property, declaration-type opt-in checks
also consult the corresponding value parameter's default-site or `param`-site
`OptIn` annotations (KUU-2070, Kotlin 2.3.10 compatibility). The correspondence
is local to that class's synthesized property declarations. This consent is
limited to the property header: it does not move annotations into property
metadata, opt in sibling declarations or callers, or change SOURCE retention.
Parameter and generated-property type checks share visitation for this pair;
a property-site opt-in alone cannot authorize the original parameter's type.
The implicit vararg array is also part of the source parameter's type, so a
property-site opt-in alone does not authorize its unsigned-array requirement.

Explicit descriptor annotation lists preserve the supplied objects and order.
These APIs do not implement serializer generation, automatic wire-name changes,
annotation inheritance or its conflict checks; those remain in KUU-1724.

### Serialization property annotation APIs (KUU-1755)

Bundled `kotlinx.serialization.Annotations.kt` declares stable public `Required`,
`Transient` and `EncodeDefault` annotations with PROPERTY targets,
MustBeDocumented and default RUNTIME retention. `EncodeDefault.mode` is non-null,
accepts named/ordinary constructor arguments and defaults to `Mode.ALWAYS`.
Its nested public `Mode` enum has ALWAYS then NEVER, ordinary enum
`entries`/`values`/`valueOf` behavior and no ExperimentalSerializationApi requirement.
Actual annotation instances use the normal constructor/equality/hash/type paths and
can be stored in explicit descriptor element annotation lists. A builder's explicit
name/count/optional flags do not change merely because these annotations are present.
The API unit covers source/cache/library and declaration metadata, not generated
Required decode rules, Transient default/wire filtering or EncodeDefault encoding;
those remain in the serializer-generation scope of KUU-1724.

Annotation class bodies allow nested enum/class/interface/object declarations and companion objects; instance functions/properties, init blocks, secondary constructors and nested type aliases remain prohibited. Nested declarations still undergo declaration-position/modifier validation, including rejection of inner classes (KUU-1755).

Referenced EncodeDefault.Mode uses the existing bundled enum nominal registration to synthesize name/entries/values/valueOf helpers when bundled source is omitted from consumer KIR (KUU-1755).

After annotation targets are resolved, synthesized primary-constructor properties
retain explicit `@property` annotations and untargeted annotations whose default
site is PROPERTY (VALUE_PARAMETER takes precedence when applicable). Their exact
classifier, occurrence ID and constructor tokens feed both metadata registration
and the ordinary annotation factory/type/constant checks. Nested and local classes
use the same idempotent routing. Other use-site annotations are not copied to the
property. Metadata may omit default RUNTIME retention; consumers resolve it from
the annotation declaration while BINARY retention remains explicit (KUU-1755).

Local annotation classifiers search the full surrounding class-scope chain
before file imports, even when synthetic local FQ names omit lexical nesting.
Primary-property `@Suppress` ranges cover only the same parameter's annotations
and default initializer, rather than the synthesized property's class-wide range.
Local nominal registration records the declaration and lexical class-scope chain
for deferred target validation. After module body inference and annotation constant
checks, TypeCheck validates each registered local class/object once, including its
header, primary/secondary constructors and parameters, members/accessors and type
annotations (including secondary-constructor types and object supertypes). This
pass runs outside speculative receiver-builder inference so diagnostic rollback
cannot discard a target violation after the nominal's idempotent registration.
It reuses the declaration target/use-site rules and resolves annotation aliases
and lexical classifiers through the same TypeSystem-aware resolver. Annotation
metadata and factories are not re-registered by this validation pass (KUU-1757).
Statement parsing retains local nominal header annotations before stripping
annotations for other local statements. Secondary-constructor declaration
annotations stop at the constructor keyword, excluding parameter/type/body
annotations from the constructor's own annotation list (KUU-1757).
Annotations on general local variables/expressions remain outside this nominal
declaration traversal.

### Producer Flow failures and cancellation (KUU-1457, KUU-1758)

Each channelFlow/callbackFlow collection owns a fresh producer continuation,
channel, and structured producer scope. Producer body and child failures settle
that Job exceptionally and fail the collection Job. A suspended collector is
interrupted, so pending buffered values need not be delivered after failure.
Each collection attempt settles its Job and restores the caller before catch or
retry handles the upstream cause. The ambient scope is not failed a second time;
ordinary produce keeps its parent ownership.
A manual close without cause cannot erase a later producer Job failure. At a
terminal receive, an already-observed producer failure precedes the close cause;
a close cause observed before cancellation precedes a later cleanup failure.
Early take/takeWhile termination ignores an unobserved channel close cause, but
preserves independent non-cancellation failures from producer cleanup.

Producer close callbacks finish before the Job publishes completion to joiners,
completion snapshots, or concurrently registered completion handlers. Collection
cancels and joins unfinished producers and their children, including a producer
parked after manual close. Collector-created children attached to the collection
Job also settle before it returns; their exceptions and parent cancellation are
included even if the producer had already completed normally. Cancelling a suspended Channel send/receive removes
only that operation's queued waiter and wakes it; other jobs sharing the channel
retain their FIFO ordering. Cancellation registration occurs outside the channel
lock and is disposed after the operation settles. Already-committed matches keep
the existing Channel ABI delivery behavior.
Generated resume labels consume a delivered exception once, so a caught producer
failure is not raised again when the caller next resumes from delay or join.
Resumed exceptions retain their Throwable handle type instead of passing through
integer boxing; catch clauses and cancellation causes preserve object identity.
Cancellation classification accepts both Runtime boxes and source nominal
subclasses, including AbortFlowException, through the runtime type hierarchy.
Cancellable continuations resolve task-backed Job identities to their completion
Job. Borrowed suspend-value loops register their own cancellation wakeup even
when driven asynchronously by an event loop; the launcher's primary continuation
is not replaced, and the handler is disposed when the borrowed loop settles.
The supplemental wake excludes continuations already reachable through the
primary continuation's suspended-call chain, preserving a later non-cancellable
suspension after the child catches cancellation.
Every resumed suspend-loop burst restores the worker's displaced task key and
Job even when it suspends again. Inline nested resumes restore burst-local
snapshots, so a parked cancelled child cannot leave its Job on a reused worker.

Channel-backed pipelines without conflate/debounce/sample process error handlers
at their operator boundary while values stream downstream. Catch/retry do not
handle downstream failures or the collecting job's cancellation cause. A user-
thrown CancellationException remains catchable while that job is active. Handler and retryWhen emissions use
the appropriate downstream collect context. A take/takeWhile boundary owns its
abort cause and normalizes only its own stop; upstream onCompletion observes the
abort while downstream onCompletion observes normal completion. Emitting a value
into a stopped downstream interrupts the handler through its throw path.
The provisional FlowCollector.emit inference shortcut runs only before builder
inference is finalized; the final pass binds the concrete collector member.

The bundled public sample uses a conflated value producer and a rendezvous
ticker inside coroutineScope. Biased select receives upstream values before
ticks, emits the latest pending value on a tick, and drops the pending tail on
normal EOF. take and collector failure cancel and join both producers, including
awaitClose cleanup. Upstream cancellation wakes the sampling scope before
producer cleanup finishes; a later cleanup failure retains its original cause.
Positive fractional Duration periods round up to milliseconds, with saturation
for Long.MAX_VALUE and infinite periods. Empty flows stop even with an enormous
ticker delay. The collector context can emit through the enclosing select
handler without recursively invoking that handler (KUU-1759).

CoroutineScope, ProducerScope and ActorScope context reads use the actual
receiver's context and Job. withContext retains a dedicated child scope even
for EmptyCoroutineContext; receiver-created children settle before return, and
escaped receivers retain their completed Job. withContext/coroutineScope/
supervisorScope detach their completed child Job so a failure caught by their
caller is not observed again while draining the parent. Synchronous withContext
entry points and resumed calls share the explicit Throwable output channel.
Public conflate and debounce currently pass through. The legacy
Runtime tagged conflate/debounce/sample operators retain their finite-batch
event model. Their timing semantics are not implemented by KUU-1759.

### Producer flow receiver builder inference (KUU-1378)

Postponed receiver-lambda constraints include monomorphic members and members
whose type parameters belong only to their declaring class. Generic constructors
and methods with their own type parameters retain their independent inference.
Before collecting member argument constraints, the actual receiver is lifted to
the generic owner. Explicit ordinary receivers use their own arguments; member
extensions use their dispatch receiver, and unrelated receivers provide no
evidence for the builder's variables. Existing monomorphic constructor constraints
remain available to infer a builder variable used in the constructor argument.
Class-only reads preserve provisional owner arguments so their result can provide
outer constraints. Spread and named varargs compare whole arrays with the
contextual array parameter. Explicit and expected type seeds contextualize
ordinary builder arguments; only concrete numeric member arguments receive a
receiver-specialized literal expectation. Constructors keep independent inference.
The final lambda pass re-infers nested member arguments rather than reusing their
provisional type. Single-member recovery checks the actual receiver's parameter
types and rejects invalid method type arguments. Fully concrete member constraints
also remain in the builder session, so a fixed expected element cannot be widened
from an incompatible send value. Speculative diagnostics use `truncate(to:)` to
restore deduplication and per-file counts before final diagnostics are emitted.

The generic builder success path preserves the selected bundled producer's
receiver/continuation launcher convention, just as regular call resolution does.
Package-qualified top-level calls use the same postponed builder constraints and
contextual lambda argument preparation as imported calls. The qualifier remains
a namespace for lowering; a local variable matching only the final function name
does not shadow that qualified declaration. Explicit type arguments also preserve
the producer's launcher convention.
Bundled source origin or validated stdlib import provenance identifies producers;
same-package user overloads retain the ordinary callable ABI. Inferred
channelFlow/callbackFlow element types and transformLatest result types
are checked through source/cache and separate library boundaries. Empty builders
without type evidence and incompatible explicit/expected types remain errors.
Producer exception propagation follows the runtime collection boundary above (KUU-1457).


### KUU-1768 proposed reflection vararg ABI

`callBy` treats absent non-optional varargs as a typed empty array; optional
varargs use the ordinary default-mask entry, and absent required non-varargs
raise IllegalArgumentException. `isOptional` and `isVararg` remain independent.
A separate packed allocating constructor reflection wrapper accepts whole arrays;
ordinary `::Ctor` invocation keeps its independently inferred callable type.
Source reference-vararg storage is Array, primitive storage stays primitive Array,
and runtime bridges keep List storage. KParameter's existing seven registration
arguments remain unchanged; erased reference component metadata is attached with
a separate private bridge. Explicit wrong empty components are rejected before
invocation. Manifest `sourceVarargStorageABI=array-v1` governs the source-only ABI
and new class/component hidden-token pair; old non-vararg reified calls keep their
one-token arity. Validation is pending and this section makes no completion claim.


Callable-reference vararg inference first attempts the packed array parameter.
A failed Array-shaped context cannot recover by treating the same Array as one
scalar element; the Kotlin 2.3.10 generic and concrete rejection probes are
retained separately from legal normal nested-array calls and packed references.
Scalar generic String adaptation allocates the inferred String component without
changing the declaration's reference-array storage class. Imported inline default
stubs preserve physical value storage, leading member-extension values, all
explicit hidden Int words and the final mask. New candidate execution is pending.

Component lowering keeps one active TypeID/SymbolID path across bound erasure
and nested reference arrays, with at most 64 active type nodes. Cyclic or deeper
imported metadata yields component 0, which propagates to its parents without
inventing an Any classifier. This is a malformed/unsupported metadata guard,
not a claim that a cyclic Kotlin source bound is legal. KParameter registration
retains unknown component 0 as a rejecting sentinel; callBy rejects explicit
arrays and cannot construct omitted reference-vararg arrays from this metadata.
Valid descriptors, reified component slots, primitive arrays, optional default
masks and the existing private runtime ABI signatures are unchanged. Direct
metadata controls and invocation counters remain proposed until executed.
