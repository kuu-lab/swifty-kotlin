@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionReduceReadsIterableReceivers() throws {
        let source = """
        fun main() {
            println(setOf(1, 2, 3).reduce { acc, value -> acc + value })
            val values: Iterable<Int> = setOf(2, 3, 4)
            println(values.reduce { acc, value -> acc * value })
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionReduceEdgeCases", expected: "6\n24\n")
    }
}

