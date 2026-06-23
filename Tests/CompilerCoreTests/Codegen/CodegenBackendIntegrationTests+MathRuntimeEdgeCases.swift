@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesMathRuntimeEdgeCases() throws {
        let source = """
        import kotlin.math.*

        fun main() {
            println(2.0.pow(10.0))
            println(log2(1024.0))
            println(ln(E))

            println(sqrt(Double.POSITIVE_INFINITY).isInfinite())
            println(sqrt(Double.NaN).isNaN())

            println(ln(Double.POSITIVE_INFINITY).isInfinite())
            println(ln(Double.NaN).isNaN())

            println((-1.0).pow(3.0))
            println((-1.0).pow(2.0))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MathRuntimeEdgeCases",
            expected:
                """
                1024.0
                10.0
                1.0
                true
                true
                true
                true
                -1.0
                1.0
                """
                + "\n"
        )
    }

    // TEST-MATH-022: End-to-end execution coverage for kotlin.math.pow IEEE 754 special cases.

    func testCodegenCompilesMathPowFloatingSpecialCases() throws {
        let source = """
        import kotlin.math.*

        fun main() {
            println((-2.0).pow(0.5).isNaN())
            println((-2.0f).pow(0.5f).isNaN())

            println((-1.0).pow(Double.POSITIVE_INFINITY) == 1.0)
            println((-1.0).pow(Double.NEGATIVE_INFINITY) == 1.0)
            println((-1.0f).pow(Float.POSITIVE_INFINITY) == 1.0f)
            println((-1.0f).pow(Float.NEGATIVE_INFINITY) == 1.0f)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MathPowFloatingSpecialCases",
            expected:
                """
                true
                true
                true
                true
                true
                true
                """
                + "\n"
        )
    }

    func testCodegenCompilesMathPowIntSpecialCases() throws {
        let source = """
        import kotlin.math.*

        fun main() {
            println((0.0).pow(-1) == Double.POSITIVE_INFINITY)
            println((0.0f).pow(-1) == Float.POSITIVE_INFINITY)

            println((-0.0).pow(-1) == Double.NEGATIVE_INFINITY)
            println((-0.0f).pow(-1) == Float.NEGATIVE_INFINITY)

            val positiveZero = Double.POSITIVE_INFINITY.pow(-1)
            println(positiveZero == 0.0)
            println(1.0 / positiveZero == Double.POSITIVE_INFINITY)

            val positiveZeroF = Float.POSITIVE_INFINITY.pow(-1)
            println(positiveZeroF == 0.0f)
            println(1.0f / positiveZeroF == Float.POSITIVE_INFINITY)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MathPowIntSpecialCases",
            expected:
                """
                true
                true
                true
                true
                true
                true
                true
                true
                """
                + "\n"
        )
    }

    func testCodegenCompilesNaNRelationalOperators() throws {
        let source = """
        fun main() {
            val doubleNaN = Double.NaN
            println(doubleNaN < 1.0)
            println(1.0 < doubleNaN)
            println(doubleNaN > 1.0)
            println(1.0 > doubleNaN)
            println(doubleNaN <= 1.0)
            println(doubleNaN >= 1.0)
            println(doubleNaN == doubleNaN)
            println(doubleNaN != doubleNaN)

            val floatNaN = Float.NaN
            println(floatNaN < 1.0f)
            println(1.0f < floatNaN)
            println(floatNaN > 1.0f)
            println(1.0f > floatNaN)
            println(floatNaN <= 1.0f)
            println(floatNaN >= 1.0f)
            println(floatNaN == floatNaN)
            println(floatNaN != floatNaN)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NaNRelationalOperators",
            expected:
                """
                false
                false
                false
                false
                false
                false
                false
                true
                false
                false
                false
                false
                false
                false
                false
                true
                """
                + "\n"
        )
    }
}

