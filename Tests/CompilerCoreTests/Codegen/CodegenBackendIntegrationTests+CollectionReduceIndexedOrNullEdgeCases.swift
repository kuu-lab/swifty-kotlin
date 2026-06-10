@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionReduceIndexedOrNullUsesListRuntime() throws {
        let source = """
        fun main() {
            val empty = listOf<Int>().reduceIndexedOrNull { index, acc, value -> acc + index * value }
            println(empty)

            val single = listOf(42).reduceIndexedOrNull { index, acc, value -> acc + index * value }
            println(single)

            val multi = listOf(1, 2, 3, 4).reduceIndexedOrNull { index, acc, value -> acc + index * value }
            println(multi)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionReduceIndexedOrNullEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "null\n42\n21\n")
        }
    }
}
