@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

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

    private var probeSource: String {
        "import kotlinx.coroutines.delay\n\n" + probeDecl
    }

    private var callerSource: String {
        "import kotlinx.coroutines.runBlocking\n\n" + callerDecl
    }

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
            let options = makeTestOptions(
                moduleName: "KspCap012UserSuspend",
                inputs: [path],
                outputPath: outputBase,
                emit: .executable
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

    @Test
    func testSuspendFunDeclaredInBundledSourceCompilesAndExecutes() throws {
        let bundledPath = "__bundled_ksp_cap_012_probe.kt"
        try withTemporaryFile(contents: callerSource) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let sourceManager = SourceManager()
            _ = sourceManager.addFile(path: bundledPath, contents: Data(probeSource.utf8), origin: .bundledStdlib)

            let options = makeTestOptions(
                moduleName: "KspCap012BundledSuspend",
                inputs: [userPath],
                outputPath: outputBase,
                emit: .executable
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: sourceManager,
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToLowering(ctx)
            try assertNoDiagnosticErrors(ctx)

            let probeFileID = try #require(ctx.sourceManager.fileID(forPath: bundledPath))
            #expect(ctx.sourceManager.path(of: probeFileID).hasPrefix("__bundled_"))

            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "44\n")
        }
    }
}
