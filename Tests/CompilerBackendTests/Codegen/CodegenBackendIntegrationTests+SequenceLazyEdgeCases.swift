@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// STDLIB-020: Sequence lazy evaluation order and sequence builder semantics.
extension CodegenBackendIntegrationTests {

    func testSequenceMapTakeEvaluatesOnlyNeededElements() throws {
        let source = """
        var counter = 0

        fun main() {
            val result = sequenceOf(1, 2, 3, 4, 5)
                .map { counter++; it * 2 }
                .take(3)
                .toList()
            println(result)
            println(counter)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceMapTakeLazy",
            expected:
                """
                [2, 4, 6]
                3
                """ + "\n"
        )
    }

    func testSequenceFilterTakeEvaluatesOnlyNeededElements() throws {
        let source = """
        var counter = 0

        fun main() {
            val result = sequenceOf(1, 2, 3, 4, 5, 6)
                .filter { counter++; it % 2 == 0 }
                .take(2)
                .toList()
            println(result)
            // filter checks 1,2,3,4 to find two even numbers; counter must be <= 4
            println(counter <= 4)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceFilterTakeLazy",
            expected:
                """
                [2, 4]
                true
                """ + "\n"
        )
    }

    func testInfiniteGenerateSequenceWithTakeTerminates() throws {
        let source = """
        fun main() {
            val naturals = generateSequence(1) { it + 1 }
            val first5 = naturals.take(5).toList()
            println(first5)
        }
        """

        try assertKotlinOutput(source, moduleName: "InfiniteGenerateSequenceTake", expected: "[1, 2, 3, 4, 5]\n")
    }

    func testGenerateSequenceTerminatesOnNull() throws {
        let source = """
        fun main() {
            val counted = generateSequence(1) { current ->
                if (current >= 4) null else current + 1
            }
            println(counted.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "GenerateSequenceNullTermination", expected: "[1, 2, 3, 4]\n")
    }

    func testSequenceBuilderYieldAndYieldAll() throws {
        let source = """
        fun main() {
            val seq = sequence {
                yield(1)
                yieldAll(listOf(2, 3, 4))
                yield(5)
            }
            println(seq.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceBuilderYieldAll", expected: "[1, 2, 3, 4, 5]\n")
    }

    func testSequenceBuilderYieldAllPreservesLazyNested() throws {
        let source = """
        var counter = 0

        fun main() {
            val inner = sequence { counter++; yield(10); counter++; yield(20); counter++; yield(30) }
            val outer = sequence { yieldAll(inner) }
            // consume only first element — inner should evaluate lazily
            val first = outer.take(1).toList()
            println(first)
            println(counter <= 1)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceBuilderYieldAllLazy",
            expected:
                """
                [10]
                true
                """ + "\n"
        )
    }

    func testSequenceFlatMapIsLazy() throws {
        let source = """
        var counter = 0

        fun main() {
            val result = sequenceOf(1, 2, 3)
                .flatMap { x -> counter++; sequenceOf(x, x * 10) }
                .take(2)
                .toList()
            println(result)
            // flatMap of first input (1) produces [1, 10]; take(2) gets them → counter == 1
            println(counter)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceFlatMapLazy",
            expected:
                """
                [1, 10]
                1
                """ + "\n"
        )
    }

    func testSequenceDistinctPreservesOrder() throws {
        let source = """
        fun main() {
            val result = sequenceOf(3, 1, 2, 1, 3, 4).distinct().toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceDistinct", expected: "[3, 1, 2, 4]\n")
    }

    func testSequenceDistinctByPreservesFirstKeyOrder() throws {
        let source = """
        fun main() {
            val result = sequenceOf(3, 1, 2, 5, 4, 7).distinctBy { it % 2 }.toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceDistinctBy", expected: "[3, 2]\n")
    }

    func testSequenceZipStopsAtShorterSequence() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3, 4)
                .zip(sequenceOf("a", "b"))
                .toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceZip", expected: "[(1, a), (2, b)]\n")
    }

    func testSequenceDropSkipsFirstN() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3, 4, 5).drop(2).toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceDrop", expected: "[3, 4, 5]\n")
    }

    func testSequenceElementAtOrElseUsesDefaultForMissingIndex() throws {
        let source = """
        fun main() {
            println(sequenceOf(10, 20, 30).elementAtOrElse(4) { it * 10 })
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceElementAtOrElse", expected: "40\n")
    }

    func testSequenceFilterKeepsMatchingElements() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3, 4, 5)
                .filter { value -> value % 2 == 0 }
                .toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilter", expected: "[2, 4]\n")
    }

    func testSequenceFilterIndexedKeepsIndexedMatches() throws {
        let source = """
        fun main() {
            val result = sequenceOf(10, 20, 30, 40)
                .filterIndexed { index, value -> index % 2 == 0 || value > 30 }
                .toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterIndexed", expected: "[10, 30, 40]\n")
    }

    func testSequenceFilterIndexedToAppendsIndexedMatches() throws {
        let source = """
        fun main() {
            val destination = mutableListOf(1)
            val result = sequenceOf(10, 20, 30, 40)
                .filterIndexedTo(destination) { index, value -> index % 2 == 0 || value > 30 }
            println(result)
            println(destination)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterIndexedTo", expected: "[1, 10, 30, 40]\n[1, 10, 30, 40]\n")
    }

    func testSequenceDropWhileSkipsLeadingMatchesOnly() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3, 1, 4).dropWhile { it < 3 }.toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceDropWhile", expected: "[3, 1, 4]\n")
    }

    func testSequenceElementAtOrNullReturnsValueOrNull() throws {
        let source = """
        fun main() {
            val values = sequenceOf(10, 20, 30)
            println(values.elementAtOrNull(1) ?: -1)
            println(values.elementAtOrNull(5) ?: -1)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceElementAtOrNull", expected: "20\n-1\n")
    }

    func testSequenceElementAtReturnsIndexedValue() throws {
        let source = """
        fun main() {
            println(sequenceOf(10, 20, 30).elementAt(1))
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceElementAt", expected: "20\n")
    }

    func testSequenceFilterIsInstanceKeepsMatchingTypes() throws {
        let source = """
        fun main() {
            val values: Sequence<Any> = sequenceOf(1, "two", 3)
            println(values.filterIsInstance<Int>().toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterIsInstance", expected: "[1, 3]\n")
    }

    func testSequenceTerminalOps() throws {
            let source = """
        fun main() {
            val seq = sequenceOf(1, 2, 3, 4, 5)

            println(seq.count())
            println(seq.indexOf(3))
            println(seq.indexOf(99))
            println(seq.indexOfFirst { it % 2 == 0 })
            println(seq.indexOfFirst { it > 10 })
            println(seq.indexOfLast { it % 2 == 0 })
            println(seq.indexOfLast { it > 10 })

            var sum = 0
            seq.forEach { sum += it }
            println(sum)

            val folded = seq.fold(0) { acc, x -> acc + x }
            println(folded)

            println(seq.intersect(listOf(2, 4, 6)))
            val foldedIndexed = seq.foldIndexed(0) { index, acc, x -> acc + index * x }
            println(foldedIndexed)
            val grouped = seq.groupBy { if (it % 2 == 0) "even" else "odd" }
            println(grouped["odd"])
            println(grouped["even"])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceTerminalOps",
            expected:
                """
                5
                2
                -1
                1
                -1
                3
                -1
                15
                15
                [2, 4]
                40
                [1, 3, 5]
                [2, 4]
                """ + "\n"
        )
    }

    func testEmptySequenceTerminals() throws {
        let source = """
        fun main() {
            val empty = emptySequence<Int>()

            println(empty.count())
            println(empty.toList())
            println(empty.firstOrNull())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EmptySequenceTerminals",
            expected:
                """
                0
                []
                null
                """ + "\n"
        )
    }

    func testSequenceFirstReturnsFirstValue() throws {
        let source = """
        fun main() {
            val result = sequenceOf(4, 5, 6).first()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFirstRuntime", expected: "4\n")
    }

    func testSequenceFirstOnEmptyThrows() throws {
        let source = """
        fun main() {
            try {
                emptySequence<Int>().first()
                println("unexpected")
            } catch (e: NoSuchElementException) {
                println("no-element")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFirstOnEmpty", expected: "no-element\n")
    }

    func testSequenceFirstOrNullReturnsFirstValue() throws {
        let source = """
        fun main() {
            val result = sequenceOf(4, 5, 6).firstOrNull()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFirstOrNullRuntime", expected: "4\n")
    }

    func testSequenceFirstOrNullOnEmpty() throws {
        let source = """
        fun main() {
            val result = emptySequence<Int>().firstOrNull()
            println(result)
            val result2 = sequenceOf(1, 2, 3).firstOrNull { it > 10 }
            println(result2)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceFirstOrNull",
            expected:
                """
                null
                null
                """ + "\n"
        )
    }

    func testAsSequenceFromList() throws {
        let source = """
        fun main() {
            val list = listOf(10, 20, 30)
            val result = list.asSequence()
                .map { it + 1 }
                .toList()
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "AsSequenceFromList", expected: "[11, 21, 31]\n")
    }

    func testSequenceAsIterableToList() throws {
        let source = """
        fun main() {
            val iterable = sequenceOf(1, 2, 3).asIterable()
            println(iterable.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceAsIterableToList", expected: "[1, 2, 3]\n")
    }

    func testSequenceAsSequenceReturnsSameSequenceSurface() throws {
        let source = """
        fun main() {
            val seq = sequenceOf(1, 2, 3).asSequence()
            println(seq.map { it + 1 }.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceAsSequence", expected: "[2, 3, 4]\n")
    }

    func testConstrainOnceThrowsOnSecondIteration() throws {
        let source = """
        fun main() {
            val seq = sequenceOf(1, 2, 3).constrainOnce()
            println(seq.toList())
            try {
                seq.toList()
                println("unexpected")
            } catch (e: IllegalStateException) {
                println("constrain-once-error")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ConstrainOnce",
            expected:
                """
                [1, 2, 3]
                constrain-once-error
                """ + "\n"
        )
    }

    func testSequenceAnyShortCircuits() throws {
        let source = """
        var counter = 0

        fun main() {
            val found = sequenceOf(1, 2, 3, 4, 5).any { counter++; it == 2 }
            println(found)
            // any stops at element 2 → counter should be <= 2
            println(counter <= 2)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceAnyShortCircuit",
            expected:
                """
                true
                true
                """ + "\n"
        )
    }

    func testSequenceAllShortCircuits() throws {
        let source = """
        var counter = 0

        fun main() {
            val allPositive = sequenceOf(1, -2, 3, 4, 5).all { counter++; it > 0 }
            println(allPositive)
            // all stops at element -2 → counter should be <= 2
            println(counter <= 2)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceAllShortCircuit",
            expected:
                """
                false
                true
                """ + "\n"
        )
    }

    func testSequenceFindShortCircuits() throws {
        let source = """
        var counter = 0

        fun main() {
            val found = sequenceOf(1, 2, 3, 4, 5).find { counter++; it == 3 }
            println(found)
            // find stops at element 3 → counter should be <= 3
            println(counter <= 3)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceFindShortCircuit",
            expected:
                """
                3
                true
                """ + "\n"
        )
    }

    func testSequenceFindLastReturnsLastMatchingValue() throws {
        let source = """
        fun main() {
            val lastEven = sequenceOf(1, 2, 3, 4, 5).findLast { value -> value % 2 == 0 }
            println(lastEven)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFindLastRuntime", expected: "4\n")
    }

    func testSequenceFilterNotNullDropsNullValues() throws {
        let source = """
        fun main() {
            val values = sequenceOf(1, null, 3)
            println(values.filterNotNull().toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterNotNullRuntime", expected: "[1, 3]\n")
    }

    func testSequenceFilterNotKeepsRejectedPredicateValues() throws {
        let source = """
        fun main() {
            val values = sequenceOf(1, 2, 3, 4, 5)
            println(values.filterNot { value -> value % 2 == 0 }.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterNotRuntime", expected: "[1, 3, 5]\n")
    }

    func testSequenceFilterIsInstanceToAppendsMatchingTypes() throws {
        let source = """
        fun main() {
            val values: Sequence<Any> = sequenceOf(1, "two", 3)
            val destination = mutableListOf<Int>(0)
            val result = values.filterIsInstanceTo(destination)
            println(result)
            println(destination)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterIsInstanceToRuntime", expected: "[0, 1, 3]\n[0, 1, 3]\n")
    }

    func testSequenceFilterToAppendsMatchingValues() throws {
        let source = """
        fun main() {
            val values = sequenceOf(1, 2, 3, 4, 5)
            val destination = mutableListOf<Int>(99)
            val result = values.filterTo(destination) { value -> value % 2 == 0 }
            println(result)
            println(destination)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterToRuntime", expected: "[99, 2, 4]\n[99, 2, 4]\n")
    }

    func testSequenceFilterNotToAppendsNonMatchingValues() throws {
        let source = """
        fun main() {
            val values = sequenceOf(1, 2, 3, 4, 5)
            val destination = mutableListOf<Int>(99)
            val result = values.filterNotTo(destination) { value -> value % 2 == 0 }
            println(result)
            println(destination)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceFilterNotToRuntime", expected: "[99, 1, 3, 5]\n[99, 1, 3, 5]\n")
    }
}

