@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSumOfUsesListRuntime() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.sumOf { it * 2 })
            println(emptyList<Int>().sumOf { it * 10 })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListSumOfRuntime", expected: "12\n0\n")
    }
}

