@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // STDLIB-COMP-FN-044: minOf(Long, Long) — 2-arg Long overload end-to-end codegen tests.

    func testCodegenCompilesMinOfLongEdgeCases() throws {
        let source = """
        fun main() {
            println(minOf(3L, 7L))
            println(minOf(-10L, -3L))
            println(minOf(0L, 0L))
            println(minOf(Long.MIN_VALUE, Long.MAX_VALUE))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MinOfLongEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                3
                -10
                0
                -9223372036854775808

                """
            )
        }
    }

    func testCodegenMinOfLongReturnsCorrectType() throws {
        let source = """
        fun minLong(a: Long, b: Long): Long = minOf(a, b)

        fun main() {
            val result: Long = minLong(100L, 200L)
            println(result)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MinOfLongReturnType",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "100\n")
        }
    }
}
