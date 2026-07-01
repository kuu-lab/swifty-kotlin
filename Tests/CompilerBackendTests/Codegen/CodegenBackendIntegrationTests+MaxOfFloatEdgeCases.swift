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

        try assertKotlinOutput(
            source,
            moduleName: "MaxOfFloatEdgeCases",
            expected:
                """
                3.5
                0.5
                2.0

                """
        )
    }

    func testCodegenCompilesMaxOfFloat3Args() throws {
        let source = """
        fun main() {
            println(maxOf(1.5f, 3.5f, 2.0f))
            println(maxOf(-1.0f, -2.0f, -0.5f))
            println(maxOf(4.0f, 4.0f, 4.0f))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MaxOfFloat3Args",
            expected:
                """
                3.5
                -0.5
                4.0

                """
        )
    }

    // maxOf(Float, Float) must propagate NaN and distinguish signed zero
    // regardless of argument order, matching kotlinc's Math.max-backed behavior
    // (verified against `kotlinc` directly) rather than a plain `>` comparison,
    // which is always false for NaN operands and treats -0.0 == 0.0.
    func testCodegenCompilesMaxOfFloatNaNAndSignedZero() throws {
        let source = """
        fun main() {
            println(maxOf(1.0f, Float.NaN))
            println(maxOf(Float.NaN, 1.0f))
            println(maxOf(0.0f, -0.0f))
            println(maxOf(-0.0f, 0.0f))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MaxOfFloatNaNAndSignedZero",
            expected:
                """
                NaN
                NaN
                0.0
                0.0

                """
        )
    }

    // Double shares the same lowering path as Float; verify NaN/signed-zero
    // handling holds for the wider type too.
    func testCodegenCompilesMaxOfDoubleNaNAndSignedZero() throws {
        let source = """
        fun main() {
            println(maxOf(1.0, Double.NaN))
            println(maxOf(Double.NaN, 1.0))
            println(maxOf(0.0, -0.0))
            println(maxOf(-0.0, 0.0))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MaxOfDoubleNaNAndSignedZero",
            expected:
                """
                NaN
                NaN
                0.0
                0.0

                """
        )
    }
}
