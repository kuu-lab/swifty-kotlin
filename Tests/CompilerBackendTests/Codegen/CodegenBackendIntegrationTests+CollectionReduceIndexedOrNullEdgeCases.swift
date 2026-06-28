@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionReduceIndexedOrNullUsesListRuntime() throws {
        let source = """
        fun main() {
            val empty = listOf<Int>().reduceIndexedOrNull { index, acc, value -> acc + index * value }
            println(empty)

            val single = listOf(42).reduceIndexedOrNull { index, acc, value -> acc + index * value }
            println(single)

            val multi = listOf(1, 2, 3, 4).reduceIndexedOrNull { index, acc, value -> acc + index * value }
            println(multi)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionReduceIndexedOrNullEdgeCases", expected: "null\n42\n21\n")
    }
}

