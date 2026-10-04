@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

// KSP-423 regression tests: predicate first/last and Array.contains must lower
// to bundled Kotlin source rather than stale kk_* runtime entries.
@Suite
struct CodegenBackendCollectionSearchHOFRegressionTests {

    @Test
    func codegenListFirstAndLastPredicateUseSourceImplementation() throws {
        let source = """
        fun main() {
            val nums = listOf(2, 4, 3, 4, 5)
            println(nums.first { it > 3 })
            println(nums.last { it < 4 })
            println(nums.find { it > 3 })
            println(nums.firstOrNull { it > 4 })
            println(nums.lastOrNull { it > 4 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListFirstLastPredicateSource",
            expected: "4\n3\n4\n5\n5\n"
        )
    }

    // KSP-973: generic Iterable.first-family calls must use bundled source implementations.
    @Test
    func codegenIterableFirstFamilyUsesSourceImplementation() throws {
        let source = """
        fun describe(values: Iterable<Int>): String {
            val first = values.first()
            val firstMatching = values.first { it > 1 }
            val firstOrNull = values.firstOrNull()
            val firstMatchingOrNull = values.firstOrNull { it > 10 }
            val firstNotNull = values.firstNotNullOf { if (it > 1) "hit" else null }
            val firstNotNullOrNull = values.firstNotNullOfOrNull { if (it > 10) "hit" else null }
            return "$first|$firstMatching|$firstOrNull|$firstMatchingOrNull|$firstNotNull|$firstNotNullOrNull"
        }

        fun main() {
            println(describe(listOf(1, 2, 3)))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IterableFirstFamilySource",
            expected: "1|2|1|null|hit|null\n"
        )
    }

    @Test
    func codegenArrayContainsUsesSourceImplementation() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.contains(2))
            println(arr.contains(4))
            println(arr.indexOf(2))
            println(arr.lastIndexOf(2))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayContainsSource",
            expected: "true\nfalse\n1\n1\n"
        )
    }

    @Test
    func codegenListAnyNoneCountUseSourceImplementation() throws {
        let source = """
        fun main() {
            val nums = listOf(1, 2, 3)
            println(nums.any())
            println(nums.none())
            println(nums.count())
            val empty = listOf<Int>()
            println(empty.any())
            println(empty.none())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListAnyNoneCountSource",
            expected: "true\nfalse\n3\nfalse\ntrue\n"
        )
    }

    @Test
    func codegenListBinarySearchUsesSourceImplementation() throws {
        let source = """
        fun main() {
            val nums = listOf(1, 3, 5, 7, 9)
            println(nums.binarySearch(5))
            println(nums.binarySearch(4))
            println(nums.binarySearch(5, 1, 4))
            println(nums.binarySearch { it - 7 })
            println(nums.binarySearchBy(7) { it })
            val natural = naturalOrder<Int>()
            println(nums.binarySearch(6, natural))
            println(nums.binarySearch(6, natural, toIndex = 4))
            println(nums.binarySearch(6, natural, fromIndex = 1, toIndex = 4))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListBinarySearchSource",
            expected: "2\n-3\n2\n3\n3\n-4\n-4\n-4\n"
        )
    }
}
#endif
