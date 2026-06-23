@testable import CompilerCore
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
}

