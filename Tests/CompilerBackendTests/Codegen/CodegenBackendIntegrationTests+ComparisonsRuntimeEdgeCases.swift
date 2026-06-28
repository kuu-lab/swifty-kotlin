@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesComparisonsRuntimeEdgeCases() throws {
        let source = """
        fun main() {
            val words = listOf("pear", "apple", "fig")
            val byLength = compareBy<String> { it.length }

            println(words.maxWithOrNull(byLength))
            println(words.minWithOrNull(byLength))

            val empty = emptyList<String>()
            println(empty.maxWithOrNull(byLength))
            println(empty.minWithOrNull(byLength))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ComparisonsRuntimeEdgeCases",
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
                fig
                null
                null
                """ + "\n"
            )
        }
    }

    func testCodegenCompilesCompareByDescendingSelector() throws {
        let source = """
        fun main() {
            val words = listOf("pear", "fig", "apple")
            val byLengthDesc = compareByDescending<String> { it.length }
            println(words.sortedWith(byLengthDesc))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CompareByDescendingSelector",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[apple, pear, fig]\n")
        }
    }

    func testCodegenListMinWithReturnsComparatorMinimumAndThrowsOnEmpty() throws {
        let source = """
        fun main() {
            println(listOf(5, 2, 3).minWith(reverseOrder<Int>()))
            try {
                emptyList<Int>().minWith(reverseOrder<Int>())
                println("missing")
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListMinWithRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "5\nempty\n")
        }
    }
}
