@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionReduceIndexedEdgeCasesTests {
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
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenCollectionReduceIndexedReadsIterableReceivers() throws {
        let source = """
        fun main() {
            println(setOf(1, 2, 3).reduceIndexed { index, acc, value -> index + acc - acc + value - value })
            val values: Iterable<Int> = setOf(4, 5, 6)
            println(values.reduceIndexed { index, acc, value -> index + acc - acc + value - value })
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionReduceIndexedEdgeCases", expected: "2\n2\n")
    }

    @Test
    func testCodegenIterableReduceIndexedRetainsCompatibilityBridge() throws {
        let source = """
        fun main() {
            val values: Iterable<Int> = setOf(4, 5, 6)
            println(values.reduceIndexed { index, acc, value -> index + acc - acc + value - value })
        }
        """

        try assertKotlinOutput(source, moduleName: "IterableReduceIndexedCompatibility", expected: "2\n")
    }
}
#endif
