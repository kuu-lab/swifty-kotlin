@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
import Testing

@Suite(.serialized)
struct CodegenBackendInlineFunctionTryCatchValueReturnTests {
    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testInlineFunctionTryCatchWithMultipleCatchBodyCallsReturnsCorrectValue() throws {
        let source = """
        inline fun <reified T> reifiedCastOrNull(value: Any?): T? {
            return try {
                value as T
            } catch (e: Exception) {
                println("logged: ${e.message}")
                null
            }
        }

        fun main() {
            println(reifiedCastOrNull<String>(42))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "InlineTryCatchReifiedCastOrNull",
            expected: "logged: ClassCastException\nnull\n"
        )
    }

    @Test
    func testInlineFunctionTryCatchWithSequentialCatchBodyCallsRunsAllStatements() throws {
        let source = """
        inline fun <reified T> castOrNullLogged(value: Any?): T? {
            return try {
                value as T
            } catch (e: Exception) {
                println("a")
                println("b")
                null
            }
        }

        fun main() {
            println(castOrNullLogged<String>(42))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "InlineTryCatchSequentialCatchBodyCalls",
            expected: "a\nb\nnull\n"
        )
    }
}
#endif
