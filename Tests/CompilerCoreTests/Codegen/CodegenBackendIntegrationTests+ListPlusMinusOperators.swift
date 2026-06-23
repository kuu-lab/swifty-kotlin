@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListMinusRemovesElementAndCollectionValues() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 2, 3)
            println(values - 2)
            println(values - listOf(2, 4))
            println(values)
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMinusRuntime", expected: "[1, 2, 3]\n[1, 3]\n[1, 2, 2, 3]\n")
    }
}

