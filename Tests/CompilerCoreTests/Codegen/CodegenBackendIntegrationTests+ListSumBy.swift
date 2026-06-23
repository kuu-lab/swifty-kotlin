@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSumByUsesListRuntime() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.sumBy { it * it })
            println(emptyList<Int>().sumBy { it * 10 })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListSumByRuntime", expected: "14\n0\n")
    }
}

