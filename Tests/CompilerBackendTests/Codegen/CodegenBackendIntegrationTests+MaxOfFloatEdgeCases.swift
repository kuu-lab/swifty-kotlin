@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesMaxOfFloatEdgeCases() throws {
        let source = """
        fun main() {
            println(maxOf(3.5f, 1.2f))
            println(maxOf(-0.5f, 0.5f))
            println(maxOf(2.0f, 2.0f))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MaxOfFloatEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                3.5
                0.5
                2.0

                """
            )
        }
    }

    // STDLIB-COMP-FN-015: maxOf(Float, Float, Float) — 3-arg Float overload
    func testCodegenCompilesMaxOfFloat3Args() throws {
        let source = """
        fun main() {
            println(maxOf(1.5f, 3.5f, 2.0f))
            println(maxOf(-1.0f, -2.0f, -0.5f))
            println(maxOf(4.0f, 4.0f, 4.0f))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MaxOfFloat3Args",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                3.5
                -0.5
                4.0

                """
            )
        }
    }
}
