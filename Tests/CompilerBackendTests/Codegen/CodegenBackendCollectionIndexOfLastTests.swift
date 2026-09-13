#if canImport(Testing)
import Testing
import Foundation
@testable import CompilerCore
@testable import CompilerBackend

@Suite
struct CodegenBackendCollectionIndexOfLastTests {
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
            target: defaultTargetTriple(),
            irFlags: []
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
    func testCodegenListIndexOfLastUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            println(listOf(1, 4, 5, 6).indexOfLast { it % 2 == 0 })
            println(listOf(1, 3, 5).indexOfLast { it % 2 == 0 })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListIndexOfLastRuntime", expected: "3\n-1\n")
    }
}
#endif
