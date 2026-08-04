@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionReduceRightIndexedEdgeCasesTests {
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
    func codegenCollectionReduceRightIndexedReadsIterableReceivers() throws {
        let source = """
        fun main() {
            println(setOf(1, 2, 3).reduceRightIndexed { index, value, acc -> index - index + value - value + acc - acc + 7 })
            val values: Iterable<Int> = setOf(4, 5, 6)
            println(values.reduceRightIndexed { index, value, acc -> index - index + value - value + acc - acc + 7 })
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionReduceRightIndexedEdgeCases", expected: "7\n7\n")
    }
}
#endif
