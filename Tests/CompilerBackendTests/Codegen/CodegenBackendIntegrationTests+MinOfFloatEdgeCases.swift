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
}
