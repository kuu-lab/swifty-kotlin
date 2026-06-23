@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenMutableListSortByDescendingMutatesPrimitiveAndObjectSelectorListsInPlace() throws {
        let source = """
        fun main() {
            val ints = mutableListOf(21, 12, 22, 11)
            ints.sortByDescending { it % 10 }
            println(ints)

            val strings = mutableListOf("b", "a", "c")
            strings.sortByDescending { it }
            println(strings)
        }
        """

        try assertKotlinOutput(source, moduleName: "MutableListSortByDescendingRuntime", expected: "[12, 22, 21, 11]\n[c, b, a]\n")
    }
}

