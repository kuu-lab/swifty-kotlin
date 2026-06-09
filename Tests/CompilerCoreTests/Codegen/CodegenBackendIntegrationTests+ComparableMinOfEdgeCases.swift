@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparableMinOfEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
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
}
