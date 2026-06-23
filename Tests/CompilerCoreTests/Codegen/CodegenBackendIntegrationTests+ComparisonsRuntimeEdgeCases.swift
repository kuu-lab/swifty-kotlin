@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesComparisonsRuntimeEdgeCases() throws {
        let source = """
        fun main() {
            val words = listOf("pear", "apple", "fig")
            val byLength = compareBy<String> { it.length }

            println(words.maxWithOrNull(byLength))
            println(words.minWithOrNull(byLength))

            val empty = emptyList<String>()
            println(empty.maxWithOrNull(byLength))
            println(empty.minWithOrNull(byLength))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparisonsRuntimeEdgeCases",
            expected:
                """
                apple
                fig
                null
                null
                """ + "\n"
        )
    }

    func testCodegenCompilesCompareByDescendingSelector() throws {
        let source = """
        fun main() {
            val words = listOf("pear", "fig", "apple")
            val byLengthDesc = compareByDescending<String> { it.length }
            println(words.sortedWith(byLengthDesc))
        }
        """

        try assertKotlinOutput(source, moduleName: "CompareByDescendingSelector", expected: "[apple, pear, fig]\n")
    }

    func testCodegenListMinWithReturnsComparatorMinimumAndThrowsOnEmpty() throws {
        let source = """
        fun main() {
            println(listOf(5, 2, 3).minWith(reverseOrder<Int>()))
            try {
                emptyList<Int>().minWith(reverseOrder<Int>())
                println("missing")
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMinWithRuntime", expected: "5\nempty\n")
    }
}

