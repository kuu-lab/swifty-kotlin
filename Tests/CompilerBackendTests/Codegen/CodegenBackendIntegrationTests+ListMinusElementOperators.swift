@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListMinusElementRemovesFirstMatchingValue() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 2, 3)
            println(values.minusElement(2))
            println(values.minusElement(element = 9))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListMinusElementOperators",
            expected:
                """
                [1, 2, 3]
                [1, 2, 2, 3]
                """ + "\n"
        )
    }
}

