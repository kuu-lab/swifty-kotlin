@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionScanIndexedUsesListRuntime() throws {
        let source = """
        fun main() {
            val empty = listOf<Int>().scanIndexed(100) { index, acc, value -> acc + index + value }
            println(empty)

            val single = listOf(5).scanIndexed(100) { index, acc, value -> acc + index + value }
            println(single)

            val multi = listOf(1, 2, 3).scanIndexed(0) { index, acc, value -> acc + value * index }
            println(multi)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionScanIndexedEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                [100]
                [100, 105]
                [0, 0, 2, 8]
                """ + "\n"
            )
        }
    }
}
