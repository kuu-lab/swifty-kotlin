@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSortedByDescendingUsesPrimitiveAndObjectSelectorPaths() throws {
        let source = """
        fun main() {
            println(listOf(21, 12, 22, 11).sortedByDescending { it % 10 })
            println(listOf("b", "a", "c").sortedByDescending { it })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListSortedByDescendingRuntime", expected: "[12, 22, 21, 11]\n[c, b, a]\n")
    }
}

