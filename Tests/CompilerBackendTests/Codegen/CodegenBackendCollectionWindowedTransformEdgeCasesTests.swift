#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCollectionWindowedTransformEdgeCasesTests {

    @Test
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

    @Test
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

    @Test
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

    @Test
    func testCodegenWindowChunkTransformKeepsBooleanCharTypeTag() throws {
        // KUU-1434: a transform returning a concrete Boolean/Char crosses the
        // erased `R` boundary of the __kk_list_*_transform bridges and of the
        // function-value ABI; without boxing it prints as 0/1 or a code point.
        let source = """
        fun main() {
            val numbers = listOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
            println(numbers.chunked(3) { chunk -> chunk.map { it % 2 == 0 } })
            println(numbers.chunked(3) { it.size == 3 })
            println(numbers.windowed(3) { it.sum() > 10 })
            println(listOf(1, 3, 2).zipWithNext { a, b -> a < b })
            println(listOf(1, 2, 3).zip(listOf(3, 2, 1)) { a, b -> a < b })
            println(listOf('a', 'b', 'c').windowed(2) { it[1] })
            println(numbers.asSequence().chunked(3) { it.size == 3 }.toList())
            val pred: (List<Int>) -> Boolean = { it.size == 2 }
            println(listOf(1, 2, 3, 4).chunked(2, pred))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "WindowChunkTransformBooleanCharTag",
            expected:
                """
                [[false, true, false], [true, false, true], [false, true, false], [true]]
                [true, true, true, false]
                [false, false, true, true, true, true, true, true]
                [true, false]
                [true, false, false]
                [b, c]
                [true, true, true, false]
                [true, true]
                """
                + "\n"
        )
    }

    @Test
    func testCodegenCollectionWindowedRejectsNonPositiveArguments() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3)
            val iterable: Iterable<Int> = list
            val array = arrayOf(1, 2, 3)

            try { list.windowed(0) } catch (e: IllegalArgumentException) { println("list-size") }
            try { list.windowed(2, step = 0) } catch (e: IllegalArgumentException) { println("list-step") }
            try { list.windowed(-1) } catch (e: IllegalArgumentException) { println("list-negative-size") }
            try { iterable.windowed(0) } catch (e: IllegalArgumentException) { println("iterable-size") }
            try { array.toList().windowed(2, step = 0) } catch (e: IllegalArgumentException) { println("array-backed-step") }
            try { list.windowed(0) { it.size } } catch (e: IllegalArgumentException) { println("transform-size") }
            try { list.windowed(2, step = 0) { it.size } } catch (e: IllegalArgumentException) { println("transform-step") }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionWindowedNonPositiveArguments",
            expected:
                """
                list-size
                list-step
                list-negative-size
                iterable-size
                array-backed-step
                transform-size
                transform-step
                """
                + "\n"
        )
    }

}
#endif
