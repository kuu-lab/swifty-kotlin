@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSubtractReturnsSetWithReceiverOrder() throws {
        let source = """
        fun main() {
            println(listOf(1, 2, 2, 3, 4).subtract(listOf(2, 4, 2)))
        }
        """

        try assertKotlinOutput(source, moduleName: "ListSubtractRuntime", expected: "[1, 3]\n")
    }
}

