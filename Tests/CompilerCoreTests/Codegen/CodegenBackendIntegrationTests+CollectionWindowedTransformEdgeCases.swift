@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionWindowedNonTransformOverloads() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3, 4, 5)
            println(list.windowed(3))
            println(list.windowed(3, 2))
            println(list.windowed(3, 2, true))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionWindowedNonTransformOverloads",
            expected:
                """
                [[1, 2, 3], [2, 3, 4], [3, 4, 5]]
                [[1, 2, 3], [3, 4, 5]]
                [[1, 2, 3], [3, 4, 5], [5]]
                """
                + "\n"
        )
    }

    func testCodegenCollectionWindowedHandlesCollectionAndSetReceivers() throws {
        let source = """
        fun main() {
            val collection: Collection<Int> = setOf(1, 2, 3, 4)
            println(collection.windowed(2))
            println(collection.windowed(3, 2, true))

            val set = setOf(4, 5, 6)
            println(set.windowed(2))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionWindowedCollectionReceivers",
            expected:
                """
                [[1, 2], [2, 3], [3, 4]]
                [[1, 2, 3], [3, 4]]
                [[4, 5], [5, 6]]
                """
                + "\n"
        )
    }

    func testCodegenCollectionWindowedTransformEdgeCases() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3, 4, 5)
            println(list.windowed(3, 2, true) { window -> window.size })
            println(list.windowed(3, 2, false) { window -> window.joinToString("-") })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionWindowedTransformEdgeCases",
            expected:
                """
                [3, 3, 1]
                [1-2-3, 3-4-5]
                """
                + "\n"
        )
    }
}

