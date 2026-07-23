@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// KSP-CAP-012: bundled ソース（`SourceManager` に `__bundled_` prefix で登録されるファイル）内で
/// 宣言された suspend fun が、ユーザーソースと同じ経路でコンパイル・実行できることを固定する回帰テスト。
/// 2026-07-08 に一時ファイルで実機確認済みだったが（TODO.md KSP-CAP-012 参照）永続的な回帰テストとして
/// 固定されていなかったため追加する。ジェネリック型引数 + suspend 関数型パラメータ + 実際の suspension
/// point（`delay`）を含み、bundled 側の関数からユーザー側の suspend ラムダを呼び出す形（KSP-674/KSP-679
/// が実際に必要とする形）を再現する。
private struct UnexpectedDiagnostics: Error, CustomStringConvertible {
    let description: String
}

@Suite
struct BundledStdlibSuspendCapabilityTests {
    // suspension point (`delay`) はジェネリック suspend fun 自体の本体に置く。ラムダ本体は
    // プリミティブ演算のみに留める — ジェネリック HOF のラムダ本体内で関数呼び出しを行うと、
    // `evaluateCandidate` が外側の未束縛な型パラメータ `R` を過剰制約する既知の別バグ
    // （TODO.md KSP-499 の 2026-07-08 調査メモ参照、`KSWIFTK-SEMA-0002`）を踏んでしまい、
    // bundled 経路自体の検証にならないため。
    private let probeDecl = """
    suspend fun <T, R> kspCap012Probe(value: T, transform: suspend (T) -> R): R {
        delay(1)
        return transform(value)
    }
    """

    private let callerDecl = """
    fun main() = runBlocking {
        val result = kspCap012Probe(11) { x -> x * 4 }
        println(result)
    }
    """

    // bundled ソースとして注入する際は、ファイル単体で自己完結した import を持たせる。
    private var probeSource: String {
        "import kotlinx.coroutines.delay\n\n" + probeDecl
    }

    // ユーザーソースとして使う際、`kspCap012Probe` は同一(root)パッケージの bundled
    // ファイルから import 無しで解決される想定 — 実際に解決できることも本テストの検証対象。
    private var callerSource: String {
        "import kotlinx.coroutines.runBlocking\n\n" + callerDecl
    }

    /// 対照群: 同じ実装をユーザーソースに置いた場合（既に動作実測済みの経路）。
    @Test
    func testSuspendFunDeclaredInUserSourceCompilesAndExecutes() throws {
        let combinedSource = """
        import kotlinx.coroutines.delay
        import kotlinx.coroutines.runBlocking

        \(probeDecl)

        \(callerDecl)
        """
        try withTemporaryFile(contents: combinedSource) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "KspCap012UserSuspend",
                inputs: [path],
                outputPath: outputBase,
                emit: .executable,
                target: defaultTargetTriple()
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToLowering(ctx)
            try assertNoDiagnosticErrors(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "44\n")
        }
    }

    /// 本題: 同じ実装を bundled ソース（`__bundled_` prefix）に置いた場合。KSP-CAP-012 が検証対象とする経路。
    @Test
    func testSuspendFunDeclaredInBundledSourceCompilesAndExecutes() throws {
        let bundledPath = "__bundled_ksp_cap_012_probe.kt"
        try withTemporaryFile(contents: callerSource) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let sourceManager = SourceManager()
            _ = sourceManager.addFile(path: bundledPath, contents: Data(probeSource.utf8), origin: .bundledStdlib)

            let options = CompilerOptions(
                moduleName: "KspCap012BundledSuspend",
                inputs: [userPath],
                outputPath: outputBase,
                emit: .executable,
                target: defaultTargetTriple()
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: sourceManager,
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToLowering(ctx)
            try assertNoDiagnosticErrors(ctx)

            // セットアップそのものが意図通り bundled 経路を通っていることを確認する。
            let probeFileID = try #require(ctx.sourceManager.fileID(forPath: bundledPath))
            #expect(ctx.sourceManager.path(of: probeFileID).hasPrefix("__bundled_"))

            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "44\n")
        }
    }

    private func assertNoDiagnosticErrors(_ ctx: CompilationContext) throws {
        guard ctx.diagnostics.hasError else { return }
        let messages = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: ", ")
        throw UnexpectedDiagnostics(description: "Unexpected diagnostics: \(messages)")
    }
}
