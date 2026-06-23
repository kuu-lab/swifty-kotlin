@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesContractEdgeCases() throws {
        let source = """
        fun main() {
            val nullable: String? = "hello"
            require(nullable != null)
            println(nullable.length)

            val anyValue: Any = "world"
            check(anyValue is String)
            println(anyValue.uppercase())

            val left: String? = "ab"
            val right: String? = "cd"
            require(left != null && right != null)
            println(left.length + right.length)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ContractEdgeCases",
            expected:
                """
                5
                WORLD
                4
                """ + "\n"
        )
    }
}

