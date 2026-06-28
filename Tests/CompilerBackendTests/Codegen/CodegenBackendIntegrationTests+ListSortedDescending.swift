@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSortedDescendingUsesPrimitiveAndObjectPaths() throws {
        let source = """
        fun main() {
            println(listOf(3, 1, 2).sortedDescending())
            println(listOf("b", "a", "c").sortedDescending())
        }
        """

        try assertKotlinOutput(source, moduleName: "ListSortedDescendingRuntime", expected: "[3, 2, 1]\n[c, b, a]\n")
    }
}

