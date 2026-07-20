@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
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
            // same XCTest method so SwiftPM does not grow the generated
            // XCTest discovery expression with another entry.
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
}
