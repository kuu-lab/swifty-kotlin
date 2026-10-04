#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendComparableMinOfEdgeCasesTests {

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
    func testCodegenCompilesComparableMinOfEdgeCases() throws {
        let source = """
        fun main() {
            // 2-arg Comparable minOf
            println(minOf("banana", "apple"))

            // 3-arg Comparable minOf
            println(minOf("cherry", "apple", "banana"))

            // vararg Comparable minOf (4 args)
            println(minOf("date", "banana", "apple", "cherry"))

            // vararg with winner at start
            println(minOf("ant", "zebra", "cat"))

            // vararg with winner at end
            println(minOf("zebra", "cat", "ant"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparableMinOfEdgeCases",
            expected:
                """
                apple
                apple
                apple
                ant
                ant

                """
        )
    }
}
#endif
