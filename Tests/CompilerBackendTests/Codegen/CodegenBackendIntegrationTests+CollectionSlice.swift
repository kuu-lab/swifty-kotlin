@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSliceUsesRangeAndIterableRuntimeHelpers() throws {
        let source = """
        fun printSlices(values: List<Int>) {
            println(values.slice(1..3))
            println(values.slice(listOf(3, 1, 3)))
        }

        fun main() {
            printSlices(listOf(10, 20, 30, 40, 50))
            println(listOf("a", "b", "c").slice(0..1))
            println(listOf("a", "b", "c").slice(listOf(2, 0)))
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionSlice", expected: "[20, 30, 40]\n[40, 20, 40]\n[a, b]\n[c, a]\n")
    }
}

