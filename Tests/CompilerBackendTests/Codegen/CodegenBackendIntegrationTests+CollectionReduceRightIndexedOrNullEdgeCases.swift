@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionReduceRightIndexedOrNullEdgeCasesTests {
    private let pipelineHelper = CodegenBackendTestSupport(name: "", testClosure: { _ in })

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try pipelineHelper.runCodegenPipeline(
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
    func testCodegenCollectionReduceRightIndexedOrNullReadsIterableReceivers() throws {
        let source = """
        fun main() {
            println(setOf(1, 2, 3).reduceRightIndexedOrNull { index, value, acc -> index - index + value - value + acc - acc + 7 } ?: -1)
            val values: Iterable<Int> = setOf(4, 5, 6)
            println(values.reduceRightIndexedOrNull { index, value, acc -> index - index + value - value + acc - acc + 7 } ?: -1)
            val emptyValues: Iterable<Int> = emptySet<Int>()
            println(emptyValues.reduceRightIndexedOrNull { index, value, acc -> index + value + acc } ?: -1)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionReduceRightIndexedOrNullEdgeCases", expected: "7\n7\n-1\n")
    }
}
#endif
