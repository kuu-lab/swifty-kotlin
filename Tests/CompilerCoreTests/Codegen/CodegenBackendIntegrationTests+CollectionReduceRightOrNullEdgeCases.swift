@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionReduceRightOrNullReadsIterableReceivers() throws {
        let source = """
        fun main() {
            println(setOf(1, 2, 3).reduceRightOrNull { value, acc -> value - value + acc - acc + 7 } ?: -1)
            val values: Iterable<Int> = setOf(4, 5, 6)
            println(values.reduceRightOrNull { value, acc -> value - value + acc - acc + 7 } ?: -1)
            val emptyValues: Iterable<Int> = emptySet<Int>()
            println(emptyValues.reduceRightOrNull { value, acc -> value + acc } ?: -1)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionReduceRightOrNullEdgeCases", expected: "7\n7\n-1\n")
    }
}

