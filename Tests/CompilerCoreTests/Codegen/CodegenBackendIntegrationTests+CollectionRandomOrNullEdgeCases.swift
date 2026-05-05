@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRandomOrNullReadsCollectionReceivers() throws {
        let source = """
        fun main() {
            println(setOf("solo").randomOrNull())
            println(emptySet<Int>().randomOrNull() == null)
            val values: Collection<Int> = setOf(7)
            println(values.randomOrNull())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionRandomOrNullEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "solo\ntrue\n7\n")
        }
    }
}
