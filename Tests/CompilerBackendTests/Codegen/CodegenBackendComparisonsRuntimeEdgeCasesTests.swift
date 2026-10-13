#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendComparisonsRuntimeEdgeCasesTests {

    @Test
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

    @Test
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
#endif
