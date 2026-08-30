#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendRangeHOFTests {

    @Test
    func testCodegenIntRangeMapIndexed() throws {
        let source = """
        fun main() {
            println((1..4).mapIndexed { index, value -> index + value })
            println((1..1).mapIndexed { index, value -> index + value })
            println((1..0).mapIndexed { index, value -> index + value })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeMapIndexed",
            expected:
                """
                [1, 3, 5, 7]
                [1]
                []
                """ + "\n"
        )
    }

    @Test
    func testCodegenIntRangeMapNotNull() throws {
        let source = """
        fun main() {
            println((1..5).mapNotNull { if (it % 2 == 0) null else it })
            println((2..2).mapNotNull { if (it % 2 == 0) null else it })
            println((1..0).mapNotNull { if (it % 2 == 0) null else it })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeMapNotNull",
            expected:
                """
                [1, 3, 5]
                []
                []
                """ + "\n"
        )
    }

    @Test
    func testCodegenIntRangeFilterIndexed() throws {
        let source = """
        fun main() {
            println((1..4).filterIndexed { index, _ -> index % 2 == 0 })
            println((10..13).filterIndexed { index, value -> index == 0 || value > 11 })
            println((1..0).filterIndexed { index, _ -> index % 2 == 0 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeFilterIndexed",
            expected:
                """
                [1, 3]
                [10, 12, 13]
                []
                """ + "\n"
        )
    }

    @Test
    func testCodegenIntRangeFindLast() throws {
        let source = """
        fun main() {
            println((1..6).findLast { it % 2 == 0 })
            println((1..5).findLast { it > 10 })
            println((1..0).findLast { it % 2 == 0 })
            println((3..3).findLast { it == 3 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeFindLast",
            expected:
                """
                6
                null
                null
                3
                """ + "\n"
        )
    }

    @Test
    func testCodegenIntRangeReduceIndexed() throws {
        // reduceIndexed starts with acc=first, then calls lambda with index starting at 1.
        // (1..4): acc=1, (idx=1,acc=1,val=2)→4, (idx=2,acc=4,val=3)→9, (idx=3,acc=9,val=4)→16
        // (5..5): single element, acc=5, no iterations → 5
        let source = """
        fun main() {
            println((1..4).reduceIndexed { index, acc, value -> acc + index + value })
            println((5..5).reduceIndexed { index, acc, value -> acc + index + value })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeReduceIndexed",
            expected:
                """
                16
                5
                """ + "\n"
        )
    }

    @Test
    func testCodegenIntRangeMapIndexedOnDescendingProgression() throws {
        // (5 downTo 3) = [5,4,3]; mapIndexed {index+value} = [0+5,1+4,2+3] = [5,5,5]
        let source = """
        fun main() {
            println((5 downTo 3).mapIndexed { index, value -> index + value })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeMapIndexedDescending",
            expected: "[5, 5, 5]\n"
        )
    }

    @Test
    func testCodegenLongRangeHOFExecution() throws {
        let source = """
        fun main() {
            println((1L..4L).mapIndexed { index, value -> index + value })
            println((1L..1L).mapIndexed { index, value -> index + value })
            println((1L..0L).mapIndexed { index, value -> index + value })

            println((1L..5L).mapNotNull { if (it % 2L == 0L) null else it })
            println((2L..2L).mapNotNull { if (it % 2L == 0L) null else it })
            println((1L..0L).mapNotNull { if (it % 2L == 0L) null else it })

            println((1L..4L).filterIndexed { index, _ -> index % 2 == 0 })
            println((10L..13L).filterIndexed { index, value -> index == 0 || value > 11L })
            println((1L..0L).filterIndexed { index, _ -> index % 2 == 0 })

            println((1L..6L).findLast { it % 2L == 0L })
            println((1L..5L).findLast { it > 10L })
            println((1L..0L).findLast { it % 2L == 0L })
            println((3L..3L).findLast { it == 3L })

            println((1L..4L).reduceIndexed { index, acc, value -> acc + index + value })
            println((5L..5L).reduceIndexed { index, acc, value -> acc + index + value })

            println((5L downTo 1L).first { it % 2L == 0L })
            println((5L downTo 1L).last { it % 2L == 0L })
            println((5L downTo 3L).mapIndexed { index, value -> index + value })
            println((1L..4L).average())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LongRangeHOFExecution",
            expected:
                """
                [1, 3, 5, 7]
                [1]
                []
                [1, 3, 5]
                []
                []
                [1, 3]
                [10, 12, 13]
                []
                6
                null
                null
                3
                16
                5
                4
                2
                [5, 5, 5]
                2.5
                """ + "\n"
        )
    }

    @Test
    func testCodegenUIntRangeMapFilterHOFExecution() throws {
        let source = """
        fun main() {
            println((1u..5u).map { it * 2u })
            println((1u..5u).mapIndexed { index, value -> index.toUInt() + value })
            println((1u..5u).mapNotNull { if (it % 2u == 0u) null else it })
            println((1u..5u).filter { it % 2u == 1u })
            println((1u..5u).filterIndexed { index, _ -> index % 2 == 0 })
            println((1u..5u).filterNot { it % 2u == 0u })
            println((5u..1u).mapNotNull { it })
            println((5u..1u).filterIndexed { index, _ -> index == 0 })
            println((5u downTo 1u).mapIndexed { index, value -> index.toUInt() + value })
            println((5u downTo 1u).filterNot { it % 2u == 0u })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "UIntRangeMapFilterHOFExecution",
            expected:
                """
                [2, 4, 6, 8, 10]
                [1, 3, 5, 7, 9]
                [1, 3, 5]
                [1, 3, 5]
                [1, 3, 5]
                [1, 3, 5]
                []
                []
                [5, 5, 5, 5, 5]
                [5, 3, 1]
                """ + "\n"
        )
    }
}
#endif
