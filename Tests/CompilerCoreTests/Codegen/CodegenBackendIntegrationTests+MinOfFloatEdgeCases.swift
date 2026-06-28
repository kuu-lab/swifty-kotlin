@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesMinOfFloatEdgeCases() throws {
        let source = """
        fun main() {
            println(minOf(3.5f, 1.2f))
            println(minOf(-0.5f, 0.5f))
            println(minOf(2.0f, 2.0f))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MinOfFloatEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                1.2
                -0.5
                2.0

                """
            )
        }
    }

    // STDLIB-COMP-FN-039: minOf(Float, Float, Float) — 3引数版はインライン比較2段階で min を求める
    func testCodegenCompilesMinOfFloat3Args() throws {
        let source = """
        fun main() {
            println(minOf(3.5f, 1.2f, 2.8f))
            println(minOf(-0.5f, 0.5f, -1.0f))
            println(minOf(2.0f, 2.0f, 2.0f))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MinOfFloat3Args",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                1.2
                -1.0
                2.0

                """
            )
        }
    }

    // STDLIB-COMP-FN-040: minOf(a: Float, vararg other: Float) with 4 arguments
    func testCodegenCompilesMinOfFloatVararg() throws {
        let source = """
        fun main() {
            println(minOf(3.5f, 1.2f, 2.8f, 0.1f))
            println(minOf(-1.0f, -3.5f, -0.5f, -2.0f))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MinOfFloatVararg",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                0.1
                -3.5

                """
            )
        }
    }
}
