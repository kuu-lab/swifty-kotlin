@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesNumericModOverloadMatrix() throws {
        let source = """
        fun main() {
            println((-7).mod(3))
            println(7.mod(-3))
            println((-7).mod(-3))
            println(7L.mod(3))
            println(7.mod(3L))
            println(10uL.mod(4u))
            println((-7.0).mod(3.0))
            println(7.0.mod(-3.0))
            println((-7.0f).mod(3.0f))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NumericModOverloadMatrix",
            expected:
                """
                2
                -2
                -1
                1
                1
                2
                2.0
                -2.0
                2.0
                """
                + "\n"
        )
    }
}

