@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionReduceRightIndexedReadsIterableReceivers() throws {
        let source = """
        fun main() {
            println(setOf(1, 2, 3).reduceRightIndexed { index, value, acc -> index - index + value - value + acc - acc + 7 })
            val values: Iterable<Int> = setOf(4, 5, 6)
            println(values.reduceRightIndexed { index, value, acc -> index - index + value - value + acc - acc + 7 })
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionReduceRightIndexedEdgeCases", expected: "7\n7\n")
    }
}

