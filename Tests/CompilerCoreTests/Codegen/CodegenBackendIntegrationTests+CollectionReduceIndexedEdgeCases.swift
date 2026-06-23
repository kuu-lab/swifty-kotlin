@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionReduceIndexedReadsIterableReceivers() throws {
        let source = """
        fun main() {
            println(setOf(1, 2, 3).reduceIndexed { index, acc, value -> index + acc - acc + value - value })
            val values: Iterable<Int> = setOf(4, 5, 6)
            println(values.reduceIndexed { index, acc, value -> index + acc - acc + value - value })
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionReduceIndexedEdgeCases", expected: "2\n2\n")
    }
}

