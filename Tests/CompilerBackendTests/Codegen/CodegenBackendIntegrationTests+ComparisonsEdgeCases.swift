@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesComparisonsEdgeCases() throws {
        let source = """
        fun main() {
            println(compareValues(1, 2))
            println(compareValues(2, 2))
            println(compareValues(3, 2))
            println(compareValues(null, 1))
            println(compareValues(1, null))

            val words = listOf("pear", "apple", "fig")
            println(words.sorted())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparisonsEdgeCases",
            expected:
                """
                -1
                0
                1
                -1
                1
                [apple, fig, pear]

                """
        )
    }
}

