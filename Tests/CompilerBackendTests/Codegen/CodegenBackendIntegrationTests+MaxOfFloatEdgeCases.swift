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
}
