@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenTypealiasUsageExecutableRunsCollectionStringPredicate() throws {
        let source = """
        typealias StringList = List<String>
        typealias Predicate<T> = (T) -> Boolean
        typealias IntPair = Pair<Int, Int>

        fun main() {
            val names: StringList = listOf("Alice", "Bob", "Charlie")
            println(names.filter { it.length > 3 })
            val pred: Predicate<String> = { it.length > 3 }
            println(pred("Hello"))
            val pair: IntPair = IntPair(1, 2)
            println("${pair.first},${pair.second}")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "TypealiasUsageRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[Alice, Charlie]\ntrue\n1,2\n")
        }
    }
}
