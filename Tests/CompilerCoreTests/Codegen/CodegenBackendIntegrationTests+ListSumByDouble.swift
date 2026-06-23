@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSumByDoubleUsesListRuntime() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.sumByDouble { if (it == 2) 1.5 else 0.25 })
            println(emptyList<Int>().sumByDouble { 1.0 })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListSumByDoubleRuntime", expected: "2.0\n0.0\n")
    }
}

