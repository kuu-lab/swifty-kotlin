@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionShuffledEdgeCasesTests {
    private func runCodegenPipeline(
        inputPath: String,
        moduleName: String,
        outputPath: String
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: .executable,
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
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenCollectionShuffledPreservesElementsForListReceivers() throws {
        let source = """
        import kotlin.random.Random

        fun printShuffled(values: List<Int>) {
            println(values.shuffled().sorted())
            println(values.shuffled(Random(42)).sorted())
        }

        fun main() {
            printShuffled(listOf(3, 1, 2))
            println(listOf(6, 4, 5).shuffled().sorted())
            println(listOf<Int>().shuffled())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionShuffledEdgeCases",
            expected:
                """
                [1, 2, 3]
                [1, 2, 3]
                [4, 5, 6]
                []
                """ + "\n"
        )
    }
}
#endif
