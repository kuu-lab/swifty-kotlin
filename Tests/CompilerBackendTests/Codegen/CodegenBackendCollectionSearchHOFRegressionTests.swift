@testable import CompilerCore
import Foundation
#if canImport(Testing)
import Testing

// KSP-423 regression tests: predicate first/last and Array.contains must lower
// to bundled Kotlin source rather than stale kk_* runtime entries.
@Suite
struct CodegenBackendCollectionSearchHOFRegressionTests {

    @Test(arguments: [false, true], [false, true])
    func codegenPrivateNestedContainsInFold(useArtifact: Bool, optimized: Bool) throws {
        if useArtifact {
            _ = try testStdlibArtifactPath()
        }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/private_nested_contains_fold.kt"
        ), encoding: .utf8)
        try assertKotlinOutput(
            source,
            moduleName: "PrivateNestedContainsFold",
            expected: "13\n13\n3\n4\n23\n",
            optLevel: optimized ? .O2 : .O0,
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    @Test(arguments: [false, true])
    func codegenListBinarySearchByGenericSelector(useArtifact: Bool) throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/list_binary_search_by_generic_selector.kt"
        ), encoding: .utf8)
        try assertKotlinOutput(
            source,
            moduleName: "ListBinarySearchByGenericSelector",
            expected: "2\n-3\n2\n2\n-3\n2\n2\n1\n1\n1\n1\n1\n-1\n-3\nselector threw\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    @Test(arguments: [false, true])
    func codegenArrayRequireNoNulls(useArtifact: Bool) throws {
        if useArtifact {
            _ = try testStdlibArtifactPath()
        }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/array_require_no_nulls.kt"
        ), encoding: .utf8)
        try assertKotlinOutput(
            source,
            moduleName: "ArrayRequireNoNulls",
            expected: "[1, 2]\nnull rejected\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }

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

    // KUU-1889: generic Array predicate search must execute through source and artifact stdlibs.
    @Test(arguments: [false, true])
    func codegenArrayIndexOfFirstUsesSourceImplementation(allowDefaultStdlibLibrary: Bool) throws {
        let source = """
        fun main() {
            val maze=arrayOf(charArrayOf('S','.'));println(maze.indexOfFirst { 'S' in it })

            val emptyCalls = intArrayOf(0)
            val emptyIndex = emptyArray<Int>().indexOfFirst { emptyCalls[0]++; true }
            println(emptyIndex)
            println(emptyCalls[0])

            val noMatchCalls = intArrayOf(0)
            val noMatchIndex = arrayOf(1, 2, 3).indexOfFirst { noMatchCalls[0]++; it == 4 }
            println(noMatchIndex)
            println(noMatchCalls[0])

            val firstCalls = intArrayOf(0)
            val firstIndex = arrayOf(4, 5, 6).indexOfFirst { firstCalls[0]++; it == 4 }
            println(firstIndex)
            println(firstCalls[0])

            val middleCalls = intArrayOf(0)
            val middleIndex = arrayOf(4, 5, 6).indexOfFirst { middleCalls[0]++; it == 5 }
            println(middleIndex)
            println(middleCalls[0])

            val lastCalls = intArrayOf(0)
            val lastIndex = arrayOf(4, 5, 6).indexOfFirst { lastCalls[0]++; it == 6 }
            println(lastIndex)
            println(lastCalls[0])

            val covariant: Array<out String> = arrayOf("a", "b")
            println(covariant.indexOfFirst { it == "b" })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayIndexOfFirstSource",
            expected: "0\n-1\n0\n-1\n3\n0\n1\n1\n2\n2\n3\n1\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
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
