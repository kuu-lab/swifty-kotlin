@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRemoveAllMutatesListsAndSets() throws {
        let source = """
        fun main() {
            val numbers = mutableListOf(1, 2, 3, 4)
            println(numbers.removeAll(listOf(2, 4)))
            println(numbers)
            println(numbers.removeAll(setOf(9)))
            println(numbers)

            val values = mutableSetOf(1, 2, 3, 4)
            println(values.removeAll(listOf(1, 4)))
            println(values)
            println(values.removeAll(setOf(9)))
            println(values)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionRemoveAllEdgeCases",
            expected:
                """
                true
                [1, 3]
                false
                [1, 3]
                true
                [2, 3]
                false
                [2, 3]
                """ + "\n"
        )
    }
}

