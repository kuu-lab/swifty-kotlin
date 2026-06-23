@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionReduceRightIndexedOrNullReadsIterableReceivers() throws {
        let source = """
        fun main() {
            println(setOf(1, 2, 3).reduceRightIndexedOrNull { index, value, acc -> index - index + value - value + acc - acc + 7 } ?: -1)
            val values: Iterable<Int> = setOf(4, 5, 6)
            println(values.reduceRightIndexedOrNull { index, value, acc -> index - index + value - value + acc - acc + 7 } ?: -1)
            val emptyValues: Iterable<Int> = emptySet<Int>()
            println(emptyValues.reduceRightIndexedOrNull { index, value, acc -> index + value + acc } ?: -1)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionReduceRightIndexedOrNullEdgeCases", expected: "7\n7\n-1\n")
    }
}

