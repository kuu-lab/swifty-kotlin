#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendMinOfFloatEdgeCasesTests {

    @Test func testCodegenCompilesMinOfFloatEdgeCases() throws {
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

    @Test func testCodegenCompilesMinOfFloat3Args() throws {
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

    @Test func testCodegenCompilesMinOfFloatVararg() throws {
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
            #expect(
                normalizedStdout == """
                0.1
                -3.5

                """
            )
        }
    }

    @Test func testCodegenCompilesMinOfFloatNaNAndSignedZero() throws {
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

    @Test func testCodegenCompilesMinOfFloatNaNMultiArg() throws {
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

    @Test func testCodegenCompilesMinOfDoubleNaNAndSignedZero() throws {
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
#endif
