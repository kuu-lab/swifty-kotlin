@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCatchesIntegerDivisionAndRemainderByZero() throws {
        let source = """
        fun main() {
            val n = 1
            val zero = 0
            try {
                println(n / zero)
            } catch (e: ArithmeticException) {
                println("int div: ArithmeticException")
            }
            try {
                println(n % zero)
            } catch (e: ArithmeticException) {
                println("int rem: ArithmeticException")
            }
            val d = 1.0
            val dz = 0.0
            println(d / dz)
            println((-d) / dz)
            println(dz / dz)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NumericDivisionByZero",
            expected:
                """
                int div: ArithmeticException
                int rem: ArithmeticException
                Infinity
                -Infinity
                NaN
                """ + "\n"
        )
    }
}

