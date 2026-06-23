@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSortedByUsesPrimitiveAndObjectSelectorPaths() throws {
        let source = """
        fun main() {
            println(listOf(22, 12, 21, 11).sortedBy { it % 10 })
            println(listOf("b", "a", "c").sortedBy { it })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListSortedByRuntime", expected: "[21, 11, 22, 12]\n[a, b, c]\n")
    }
}

