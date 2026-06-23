@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionShuffledPreservesElementsForListReceivers() throws {
        let source = """
        import kotlin.random.Random

        fun printShuffled(values: List<Int>) {
            println(values.shuffled().sorted())
            println(values.shuffled(Random(42)).sorted())
        }

        fun main() {
            printShuffled(listOf(3, 1, 2))
            println(listOf(6, 4, 5).shuffled().sorted())
            println(listOf<Int>().shuffled())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionShuffledEdgeCases",
            expected:
                """
                [1, 2, 3]
                [1, 2, 3]
                [4, 5, 6]
                []
                """ + "\n"
        )
    }
}

