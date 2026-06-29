@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenMutableListSortByMutatesPrimitiveAndObjectSelectorListsInPlace() throws {
        let source = """
        fun main() {
            val ints = mutableListOf(22, 12, 21, 11)
            ints.sortBy { it % 10 }
            println(ints)

            val strings = mutableListOf("b", "a", "c")
            strings.sortBy { it }
            println(strings)
        }
        """

        try assertKotlinOutput(source, moduleName: "MutableListSortByRuntime", expected: "[21, 11, 22, 12]\n[a, b, c]\n")
    }
}

