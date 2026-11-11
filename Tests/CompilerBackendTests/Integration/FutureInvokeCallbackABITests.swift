@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct FutureInvokeCallbackABITests {
    @Test(arguments: [0, 2])
    func callbacksUseRuntimeABI(optimization: Int) throws {
        let source = """
        fun forwarded(code: (Int) -> Int, value: Int): Int = invokeFuture(code, value)

        fun main() {
            printResult(if (invokeFuture({ value: Int -> value + 1 }, 41) == 42) "direct" else "wrong")
            val offset = 7
            val code: (Int) -> Int = { it + offset }
            printResult(if (forwarded(code, 35) == 42) "captured" else "wrong")
            try {
                forwarded({ throw Throwable("callback") }, 1)
                printResult("missed")
            } catch (e: Throwable) {
                printResult("callback")
            }
        }
        """
        try withTemporaryFile(contents: source) { input in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            let sourceManager = SourceManager()
            _ = sourceManager.addFile(path: "__bundled_future_abi.kt", contents: Data("""
            package kotlin
            @KsSymbolName("kk_future_invoke")
            external fun <T, R> invokeFuture(code: (T) -> R, value: T): R
            @KsSymbolName("__kk_println_raw")
            external fun printResult(value: String)
            open class Throwable {
                @KsSymbolName("__kk_throwable_new")
                constructor(message: String?)
            }
            """.utf8), origin: .bundledStdlib)
            let ctx = CompilationContext(options: CompilerOptions(
                moduleName: "FutureInvokeABI", inputs: [input], outputPath: output,
                emit: .executable, target: .hostDefault(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                includeStdlib: false, allowDefaultStdlibLibrary: false
            ), sourceManager: sourceManager, diagnostics: DiagnosticEngine(), interner: StringInterner())
            try runToLowering(ctx)
            try assertNoDiagnosticErrors(ctx)
            do {
                try CodegenPhase().run(ctx)
            } catch {
                try assertNoDiagnosticErrors(ctx)
                throw error
            }
            try assertNoDiagnosticErrors(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "direct\ncaptured\ncallback\n")
        }
    }

}
