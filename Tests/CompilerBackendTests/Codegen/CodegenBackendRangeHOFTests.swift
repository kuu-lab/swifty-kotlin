#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendRangeHOFTests {

    @Test
    func testCodegenIntProgressionPositiveStepHOFs() throws {
        let source = """
        fun main() {
            println((1..10 step 3).map { it })
            println((1..10 step 3).filter { it > 4 })
            val progression = 1..10 step 3
            progression.forEach { print(it) }
            println()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntProgressionPositiveStepHOFs",
            expected:
                """
                [1, 4, 7, 10]
                [7, 10]
                14710
                """ + "\n"
        )
    }

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
    func testCodegenUIntRangeHOFExecution() throws {
        let source = """
        fun main() {
            println((1u..5u).fold(10u) { accumulator, value -> accumulator + value })
            println((1u..5u).foldIndexed(10u) { index, accumulator, value -> accumulator + index.toUInt() + value })
            println((1u..5u).reduce { accumulator, value -> accumulator + value })
            println((1u..5u).reduceIndexed { index, accumulator, value -> accumulator + index.toUInt() + value })
            println((1u..5u).find { it % 2u == 0u })
            println((1u..5u).findLast { it % 2u == 0u })
            println((1u..5u).first { it > 3u })
            println((1u..5u).firstOrNull { it > 8u })
            println((1u..5u).last { it < 4u })
            println((1u..5u).lastOrNull { it > 8u })
            println((1u..5u).any { it == 5u })
            println((1u..5u).all { it > 0u })
            println((1u..5u).none { it > 5u })
            (1u..3u).forEach { print("$it ") }
            println()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "UIntRangeHOFExecution",
            expected:
                """
                25
                35
                15
                25
                2
                4
                4
                null
                3
                null
                true
                true
                true
                """ + "\n1 2 3 \n"
        )
    }

    @Test
    func testCodegenULongRangeHOFExecution() throws {
        let source = """
        fun main() {
            println((1uL..5uL).fold(10uL) { accumulator, value -> accumulator + value })
            println((1uL..5uL).foldIndexed(10uL) { index, accumulator, value -> accumulator + index.toULong() + value })
            println((1uL..5uL).reduce { accumulator, value -> accumulator + value })
            println((1uL..5uL).reduceIndexed { index, accumulator, value -> accumulator + index.toULong() + value })
            println((1uL..5uL).find { it % 2uL == 0uL })
            println((1uL..5uL).findLast { it % 2uL == 0uL })
            println((1uL..5uL).first { it > 3uL })
            println((1uL..5uL).firstOrNull { it > 8uL })
            println((1uL..5uL).last { it < 4uL })
            println((1uL..5uL).lastOrNull { it > 8uL })
            println((1uL..5uL).any { it == 5uL })
            println((1uL..5uL).all { it > 0uL })
            println((1uL..5uL).none { it > 5uL })
            (1uL..3uL).forEach { print("$it ") }
            println()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ULongRangeHOFExecution",
            expected:
                """
                25
                35
                15
                25
                2
                4
                4
                null
                3
                null
                true
                true
                true
                """ + "\n1 2 3 \n"
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
    func testCodegenIntRangeReduce() throws {
        // KSP-1011 regression: a second source-backed `iterator()` declared
        // on Map (kotlin.collections.Map<out K, V>.iterator()) once widened
        // the by-simple-name candidate pool that this bundled `reduce`
        // body's implicit-receiver `iterator()` call resolves against,
        // binding it to the Map-only implementation for every Iterable
        // receiver — including this IntRange — and crashing at runtime
        // instead of computing the sum.
        let source = """
        fun main() {
            println((1..4).reduce { acc, v -> acc + v })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeReduce",
            expected: "10\n"
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

    @Test
    func testCodegenUIntRangeIteratorStepAndWindowingExecution() throws {
        let source = """
        fun main() {
            println((1u..5u).take(3))
            println((1u..5u).drop(2))
            println((1u..5u).chunked(2))
            println((1u..5u).windowed(3))
            println((1u..5u).windowed(3, 2, true))
            println((1u..5u step 2).take(2))
            println((5u downTo 1u).windowed(2, 2, true))
            for (value in 1u..5u) print("$value ")
            println()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "UIntRangeIteratorStepAndWindowingExecution",
            expected:
                """
                [1, 2, 3]
                [3, 4, 5]
                [[1, 2], [3, 4], [5]]
                [[1, 2, 3], [2, 3, 4], [3, 4, 5]]
                [[1, 2, 3], [3, 4, 5], [5]]
                [1, 3]
                [[5, 4], [3, 2], [1]]
                """ + "\n1 2 3 4 5 \n"
        )
    }

    @Test
    func testCodegenULongRangeMapFilterHOFExecution() throws {
        let source = """
        fun main() {
            println((1uL..5uL).map { it * 2uL })
            println((1uL..5uL).mapIndexed { index, value -> index.toULong() + value })
            println((1uL..5uL).mapNotNull { if (it % 2uL == 0uL) null else it })
            println((1uL..5uL).filter { it % 2uL == 1uL })
            println((1uL..5uL).filterIndexed { index, _ -> index % 2 == 0 })
            println((1uL..5uL).filterNot { it % 2uL == 0uL })
            println((5uL..1uL).mapNotNull { it })
            println((5uL..1uL).filterIndexed { index, _ -> index == 0 })
            println((5uL downTo 1uL).mapIndexed { index, value -> index.toULong() + value })
            println((5uL downTo 1uL).filterNot { it % 2uL == 0uL })
            println((1uL..9uL step 2).mapIndexed { index, value -> index.toULong() + value })
            println((1uL..9uL step 2).filterNot { it > 4uL })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ULongRangeMapFilterHOFExecution",
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
                [1, 4, 7, 10, 13]
                [1, 3]
                """ + "\n"
        )
    }

    @Test
    func testCodegenULongRangeIteratorStepAndWindowingExecution() throws {
        let source = """
        fun main() {
            println((1UL..5UL).take(3))
            println((1UL..5UL).drop(2))
            println((1UL..5UL).chunked(2))
            println((1UL..5UL).windowed(3))
            println((1UL..5UL).windowed(3, 2, true))
            println((1UL..5UL step 2).take(2))
            println((5UL downTo 1UL).windowed(2, 2, true))
            for (value in 1UL..5UL) print("$value ")
            println()
            println((0UL..ULong.MAX_VALUE step 3).last)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ULongRangeIteratorStepAndWindowingExecution",
            expected:
                """
                [1, 2, 3]
                [3, 4, 5]
                [[1, 2], [3, 4], [5]]
                [[1, 2, 3], [2, 3, 4], [3, 4, 5]]
                [[1, 2, 3], [3, 4, 5], [5]]
                [1, 3]
                [[5, 4], [3, 2], [1]]
                """ + "\n1 2 3 4 5 \n18446744073709551615\n"
        )
    }

    @Test
    func testCodegenULongRangeStepNearMaxValueDoesNotWrap() throws {
        let source = """
        fun main() {
            val nearMax = (ULong.MAX_VALUE - 4uL)..ULong.MAX_VALUE step 3
            println(nearMax.toList())
            println(((ULong.MAX_VALUE - 1uL)..ULong.MAX_VALUE step 3).toList())
            println((ULong.MAX_VALUE downTo (ULong.MAX_VALUE - 5uL) step 2).toList())
            println(nearMax.take(1))
            println(nearMax.drop(1))
            println(nearMax.chunked(1))
            println(nearMax.windowed(2, 1, true))
            for (value in (ULong.MAX_VALUE - 4uL)..ULong.MAX_VALUE step 3) print("$value ")
            println()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ULongRangeStepNearMaxValueDoesNotWrap",
            expected:
                """
                [18446744073709551611, 18446744073709551614]
                [18446744073709551614]
                [18446744073709551615, 18446744073709551613, 18446744073709551611]
                [18446744073709551611]
                [18446744073709551614]
                [[18446744073709551611], [18446744073709551614]]
                [[18446744073709551611, 18446744073709551614], [18446744073709551614]]
                """ + "\n18446744073709551611 18446744073709551614 \n"
        )
    }

    @Test
    func testCodegenEmptyRangeFirstLastThrowNoSuchElementException() throws {
        let source = """
        fun firstOf(range: IntRange): Int = range.first()
        fun lastOf(range: IntRange): Int = range.last()

        fun main() {
            println((1..4).first())
            println((1..4).last())
            println((1..0).first)
            println((1..0).last)

            try {
                println((1..0).first())
            } catch (e: NoSuchElementException) {
                println("empty-first")
            }
            try {
                println((1..0).last())
            } catch (e: NoSuchElementException) {
                println("empty-last")
            }
            try {
                println((0 until 0).first())
            } catch (e: NoSuchElementException) {
                println("until-first")
            }
            try {
                println(firstOf(1..0))
            } catch (e: NoSuchElementException) {
                println("param-first")
            }
            try {
                println(lastOf(1..0))
            } catch (e: NoSuchElementException) {
                println("param-last")
            }

            println((1..0).firstOrNull())
            println((1..0).lastOrNull())
            try {
                println((1..0).first { it > 0 })
            } catch (e: NoSuchElementException) {
                println("pred-first")
            }
            try {
                println((1..0).last { it > 0 })
            } catch (e: NoSuchElementException) {
                println("pred-last")
            }

            try {
                println((1L..0L).first())
            } catch (e: NoSuchElementException) {
                println("long-first")
            }
            try {
                println(('b'..'a').first())
            } catch (e: NoSuchElementException) {
                println("char-first")
            }
            try {
                println((1u..0u).first())
            } catch (e: NoSuchElementException) {
                println("uint-first")
            }
            try {
                println((1uL..0uL).last())
            } catch (e: NoSuchElementException) {
                println("ulong-last")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EmptyRangeFirstLast",
            expected:
                """
                1
                4
                1
                0
                empty-first
                empty-last
                until-first
                param-first
                param-last
                null
                null
                pred-first
                pred-last
                long-first
                char-first
                uint-first
                ulong-last
                """ + "\n"
        )
    }
}
#endif
