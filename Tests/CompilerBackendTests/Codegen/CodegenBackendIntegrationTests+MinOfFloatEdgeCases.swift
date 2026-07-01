@testable import CompilerCore
@testable import CompilerBackend
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

        try assertKotlinOutput(
            source,
            moduleName: "MinOfFloatEdgeCases",
            expected:
                """
                1.2
                -0.5
                2.0

                """
        )
    }

    func testCodegenCompilesMinOfFloat3Args() throws {
        let source = """
        fun main() {
            println(minOf(3.5f, 1.2f, 2.8f))
            println(minOf(-0.5f, 0.5f, -1.0f))
            println(minOf(2.0f, 2.0f, 2.0f))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MinOfFloat3Args",
            expected:
                """
                1.2
                -1.0
                2.0

                """
        )
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

    // minOf(Float, Float) must propagate NaN and distinguish signed zero
    // regardless of argument order, matching kotlinc's Math.min-backed behavior
    // (verified against `kotlinc` directly) rather than a plain `<` comparison,
    // which is always false for NaN operands and treats -0.0 == 0.0.
    func testCodegenCompilesMinOfFloatNaNAndSignedZero() throws {
        let source = """
        fun main() {
            println(minOf(1.0f, Float.NaN))
            println(minOf(Float.NaN, 1.0f))
            println(minOf(0.0f, -0.0f))
            println(minOf(-0.0f, 0.0f))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MinOfFloatNaNAndSignedZero",
            expected:
                """
                NaN
                NaN
                -0.0
                -0.0

                """
        )
    }

    // 3-arg and vararg minOf(Float) must propagate NaN through every pairwise
    // step, not just the first/last comparison.
    func testCodegenCompilesMinOfFloatNaNMultiArg() throws {
        let source = """
        fun main() {
            println(minOf(1.0f, Float.NaN, 2.0f))
            println(minOf(2.0f, Float.NaN, 1.0f))
            println(minOf(1.0f, Float.NaN, 2.0f, 3.0f))
            println(minOf(0.0f, -0.0f, 0.0f, 0.0f))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MinOfFloatNaNMultiArg",
            expected:
                """
                NaN
                NaN
                NaN
                -0.0

                """
        )
    }

    // Double shares the same lowering path as Float; verify NaN/signed-zero
    // handling holds for the wider type too.
    func testCodegenCompilesMinOfDoubleNaNAndSignedZero() throws {
        let source = """
        fun main() {
            println(minOf(1.0, Double.NaN))
            println(minOf(Double.NaN, 1.0))
            println(minOf(0.0, -0.0))
            println(minOf(-0.0, 0.0))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MinOfDoubleNaNAndSignedZero",
            expected:
                """
                NaN
                NaN
                -0.0
                -0.0

                """
        )
    }
}
