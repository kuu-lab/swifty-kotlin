@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenMutableListSortMutatesPrimitiveAndObjectListsInPlace() throws {
        let source = """
        fun main() {
            val ints = mutableListOf(5, 3, 8, 1, 4)
            ints.sort()
            println(ints)

            val strings = mutableListOf("b", "a", "c")
            strings.sort()
            println(strings)
        }
        """

        try assertKotlinOutput(source, moduleName: "MutableListSortRuntime", expected: "[1, 3, 4, 5, 8]\n[a, b, c]\n")
    }
}

