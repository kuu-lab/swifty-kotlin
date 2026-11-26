#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCollectionFlatMapTests {

    @Test func testCodegenListFlatMapBasic() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            val result = values.flatMap { listOf(it, it * 10) }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionFlatMapBasic", expected: "[1, 10, 2, 20, 3, 30]\n")
    }

    @Test func testCodegenListFlatMapWithEmptyInput() throws {
        let source = """
        fun main() {
            val values = emptyList<Int>()
            val result = values.flatMap { listOf(it, it * 10) }
            println(result)
            println(result.size)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionFlatMapEmptyInput", expected: "[]\n0\n")
    }

    @Test func testCodegenListFlatMapWithConditionalEmptySubList() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3, 4, 5)
            val result = values.flatMap { if (it % 2 == 0) listOf(it) else listOf<Int>() }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionFlatMapConditionalEmpty", expected: "[2, 4]\n")
    }

    @Test func testCodegenListFlatMapIndexed() throws {
        let source = """
        fun main() {
            val values = listOf(10, 20, 30)
            val result = values.flatMapIndexed { index, value -> listOf(index, value) }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionFlatMapIndexed", expected: "[0, 10, 1, 20, 2, 30]\n")
    }

    @Test func testCodegenListFlatMapWithRangeTransform() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.flatMap { 1..it })
            println(values.flatMap { it..it })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionFlatMapRangeTransform",
            expected: "[1, 1, 2, 1, 2, 3]\n[1, 2, 3]\n"
        )
    }

    @Test func testCodegenListFlatMapWithNonListIterableTransforms() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.flatMap { setOf(it) })
            println(values.flatMap { sequenceOf(it) })
            val f: (Int) -> Iterable<Int> = { 1..it }
            println(values.flatMap(f))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionFlatMapNonListIterableTransforms",
            expected: "[1, 2, 3]\n[1, 2, 3]\n[1, 1, 2, 1, 2, 3]\n"
        )
    }

    @Test func testCodegenListFlatMapRangeTransformKeepsElementType() throws {
        let source = """
        fun main() {
            val result: List<Int> = listOf(1, 2, 3).flatMap { 1..it }
            println(result)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionFlatMapRangeElementType",
            expected: "[1, 1, 2, 1, 2, 3]\n"
        )
    }

    @Test func testCodegenListFlatMapToWithRangeTransform() throws {
        let source = """
        fun main() {
            val destination = mutableListOf<Int>()
            println(listOf(1, 2, 3).flatMapTo(destination) { 1..it })
            println(listOf(1, 2, 3).flatMapTo(mutableListOf<Int>()) { it..it })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionFlatMapToRangeTransform",
            expected: "[1, 1, 2, 1, 2, 3]\n[1, 2, 3]\n"
        )
    }

    @Test func testCodegenListFlatMapIndexedWithRangeTransform() throws {
        let source = """
        fun main() {
            println(listOf(1, 2, 3).flatMapIndexed { i, v -> v..(v + i) })
            println(listOf(1, 2, 3).flatMapIndexedTo(mutableListOf<Int>()) { i, v -> v..(v + i) })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionFlatMapIndexedRangeTransform",
            expected: "[1, 2, 3, 3, 4, 5]\n[1, 2, 3, 3, 4, 5]\n"
        )
    }

    @Test func testCodegenIntArrayFlatMapWithRangeTransform() throws {
        let source = """
        fun main() {
            println(intArrayOf(1, 2, 3).flatMap { 1..it })
            println(arrayOf(1, 2, 3).flatMap { 1..it })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "PrimitiveArrayFlatMapRangeTransform",
            expected: "[1, 1, 2, 1, 2, 3]\n[1, 1, 2, 1, 2, 3]\n"
        )
    }
}
#endif
