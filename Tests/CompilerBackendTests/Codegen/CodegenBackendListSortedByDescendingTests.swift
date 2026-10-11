#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendListSortedByDescendingTests {

    @Test
    func testCodegenListSortedByDescendingUsesPrimitiveAndObjectSelectorPaths() throws {
        let source = """
        fun main() {
            println(listOf(21, 12, 22, 11).sortedByDescending { it % 10 })
            println(listOf("b", "a", "c").sortedByDescending { it })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListSortedByDescendingRuntime", expected: "[12, 22, 21, 11]\n[c, b, a]\n")
    }

    @Test
    func testCodegenListComparatorConsumersHonorContravarianceAndNullableSelector() throws {
        let source = """
        fun main() {
            val values = listOf("a", "bb", "ccc", "dddd")
            val comparator: Comparator<Any> = Comparator { left, right ->
                left.toString().length - right.toString().length
            }

            println(values.maxWith(comparator))
            println(values.maxWithOrNull(comparator))
            println(values.minWith(comparator))
            println(values.minWithOrNull(comparator))
            println(values.sortedWith(comparator))
            println(values.sortedByDescending { value ->
                if (value.length % 2 == 0) null else value.length
            })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListComparatorConsumersRuntime",
            expected: "dddd\ndddd\na\na\n[a, bb, ccc, dddd]\n[ccc, a, bb, dddd]\n"
        )
    }
}
#endif
