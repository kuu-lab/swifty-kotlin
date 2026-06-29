@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionPartitionSplitsElementsAndHandlesEmptySources() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3, 4, 5)
            val (evens, odds) = values.partition { it % 2 == 0 }
            println(evens)
            println(odds)

            val empty = emptyList<Int>()
            val (matchingEmpty, restEmpty) = empty.partition { it > 0 }
            println(matchingEmpty.size)
            println(restEmpty.size)

            val (allMatch, noneLeft) = listOf(2, 4, 6).partition { it % 2 == 0 }
            println(allMatch)
            println(noneLeft.size)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionPartitionEdgeCases", expected: "[2, 4]\n[1, 3, 5]\n0\n0\n[2, 4, 6]\n0\n")
    }
}

