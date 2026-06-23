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
}

