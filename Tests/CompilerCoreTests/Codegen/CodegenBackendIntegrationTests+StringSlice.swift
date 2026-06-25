@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenStringSliceUsesRangeAndIterableRuntimeHelpers() throws {
        let source = """
        fun main() {
            val s = "hello world"
            println(s.slice(0..4))
            println(s.slice(6..10))
            println(s.slice(0 until 5))
            println(s.slice(listOf(0, 1, 4)))

            val r = 0..4
            println(s.slice(r))

            println("abcde".slice(1..3))
            println("abcde".slice(listOf(4, 2, 0)))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringSlice",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "hello\nworld\nhello\nheo\nhello\nbcd\neca\n")
        }
    }

    func testCodegenStringSliceEmptyRange() throws {
        let source = """
        fun main() {
            println("hello".slice(listOf<Int>()))
            println("hello".slice(2..1))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringSliceEmpty",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "\n\n")
        }
    }
}
