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
