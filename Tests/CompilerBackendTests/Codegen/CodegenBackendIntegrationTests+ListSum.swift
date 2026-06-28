@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSumUsesListRuntime() throws {
        let source = """
        fun main() {
            println(listOf(1, 2, 3, 4).sum())
            println(emptyList<Int>().sum())
        }
        """

        try assertKotlinOutput(source, moduleName: "ListSumRuntime", expected: "10\n0\n")
    }
}

