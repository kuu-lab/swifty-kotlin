#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendAssertEdgeCasesTests {

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
    func testCodegenCompilesAssertEdgeCases() throws {
        let source = """
        fun main() {
            var counter = 0

            require(true) { counter += 1; "require should not run" }
            check(true) { counter += 10; "check should not run" }
            println(counter)

            try {
                require(false) { "bad-arg" }
            } catch (e: Throwable) {
                println(e.message)
            }

            try {
                check(false) { "bad-state" }
            } catch (e: Throwable) {
                println(e.message)
            }

            try {
                error("boom")
            } catch (e: Throwable) {
                println(e.message)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "AssertEdgeCases",
            expected:
                """
                0
                bad-arg
                bad-state
                boom
                """ + "\n"
        )
    }
}
#endif
