#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendContractEdgeCasesTests {

    private func runCodegenPipeline(
        inputPath: String,
        moduleName: String,
        emit: EmitMode,
        outputPath: String
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: emit,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
        return ctx
    }

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenCompilesContractEdgeCases() throws {
        let source = """
        fun main() {
            val nullable: String? = "hello"
            require(nullable != null)
            println(nullable.length)

            val anyValue: Any = "world"
            check(anyValue is String)
            println(anyValue.uppercase())

            val left: String? = "ab"
            val right: String? = "cd"
            require(left != null && right != null)
            println(left.length + right.length)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ContractEdgeCases",
            expected:
                """
                5
                WORLD
                4
                """ + "\n"
        )
    }
}
#endif
