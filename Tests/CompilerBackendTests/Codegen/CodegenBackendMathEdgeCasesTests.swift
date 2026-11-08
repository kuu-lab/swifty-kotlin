#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendMathEdgeCasesTests {

    @Test
    func testCodegenCompilesMathEdgeCases() throws {
        let source = """
        import kotlin.math.*

        fun main() {
            println(sqrt(16.0))
            println(sqrt(-1.0).isNaN())

            println(abs(-42))
            println(abs(Double.NEGATIVE_INFINITY).isInfinite())

            println(round(2.4))
            println(round(-2.4))

            println(ceil(2.1))
            println(floor(-2.1))

            println(ceil(Double.NaN).isNaN())
            println(floor(Double.POSITIVE_INFINITY).isInfinite())

            // DEBT-DIFF-006 regression: keep List<Double> iteration in the
            // same test method so SwiftPM does not grow the generated
            // Swift Testing discovery expression with another entry.
            val values = listOf(3.2, 3.7, -2.3)
            for (value in values) {
                println(round(value))
                println(value.roundToInt())
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MathEdgeCases",
            expected:
                """
                4.0
                true
                42
                true
                2.0
                -2.0
                3.0
                -3.0
                true
                true
                3.0
                3
                4.0
                4
                -2.0
                -2
                """
                + "\n"
        )
    }

    @Test
    func testCodegenMathFloatPureKotlinOverloads() throws {
        let source = """
        import kotlin.math.*

        fun main() {
            println(sqrt(4.0f))
            println(ceil(2.3f))
            println(floor(2.7f))
            println(round(2.7f))
            println(truncate(2.7f))
            println(sin(0.0f))
            println(cos(0.0f))
            println(tan(0.0f))
            println(exp(0.0f))
            println(ln(1.0f))
            println(log10(100.0f))
            println(log2(8.0f))
            println(hypot(3.0f, 4.0f))
            println(2.0f.pow(3.0f))
            println(2.0f.pow(3))
            println(7.0f.IEEErem(3.0f))
            println(sinh(0.0f))
            println(cosh(0.0f))
            println(tanh(0.0f))
            println(cbrt(27.0f))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MathFloatPureKotlin",
            expected:
                """
                2.0
                3.0
                2.0
                3.0
                2.0
                0.0
                1.0
                0.0
                1.0
                0.0
                2.0
                3.0
                5.0
                8.0
                8.0
                1.0
                0.0
                1.0
                0.0
                3.0
                """
                + "\n"
        )
    }

}
#endif
