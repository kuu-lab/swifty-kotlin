@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenArrayReduceComputesSum() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.reduce { acc, x -> acc + x })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayReduce", expected: "6\n")
    }

    func testCodegenArrayReduceOrNullReturnsValueForNonEmptyArray() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.reduceOrNull { acc, x -> acc + x })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayReduceOrNull", expected: "6\n")
    }

    func testCodegenArrayReduceIndexedAccumulatesWithIndex() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            // index=1: acc=1, x=2 → 1+2*1=3
            // index=2: acc=3, x=3 → 3+3*2=9
            println(arr.reduceIndexed { index, acc, x -> acc + x * index })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayReduceIndexed", expected: "9\n")
    }

    func testCodegenArrayFoldComputesSumWithInitial() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.fold(10) { acc, x -> acc + x })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayFold", expected: "16\n")
    }

    func testCodegenArrayFoldIndexedAccumulatesWithIndexAndInitial() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            // index=0: acc=0, x=1 → 0+1*0=0
            // index=1: acc=0, x=2 → 0+2*1=2
            // index=2: acc=2, x=3 → 2+3*2=8
            println(arr.foldIndexed(0) { index, acc, x -> acc + x * index })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayFoldIndexed", expected: "8\n")
    }

    func testCodegenArrayFlatMapExpandsElements() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            val result = arr.flatMap { x -> listOf(x, x * 10) }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayFlatMap", expected: "[1, 10, 2, 20, 3, 30]\n")
    }

    // MARK: - Array HOF gap fix (mapIndexed/filterIndexed/mapNotNull/filterNot/filterNotNull)
    //
    // These previously failed Sema member resolution outright with
    // "Unresolved member function" on Array receivers, despite the identically
    // named List members already working. See
    // CallTypeChecker+ArrayMemberFallback.swift, CollectionLiteralLoweringPass+
    // VirtualCallRewrite+Array.swift, and CallLowerer+UnresolvedMemberCalls.swift.

    func testCodegenArrayMapIndexedComputesIndexedTransform() throws {
        let source = """
        fun main() {
            val arr = arrayOf(10, 20, 30)
            // index=0: 0+10=10; index=1: 1+20=21; index=2: 2+30=32
            println(arr.mapIndexed { index, value -> index + value })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayMapIndexed", expected: "[10, 21, 32]\n")
    }

    func testCodegenArrayFilterIndexedKeepsOnlyIndexMatches() throws {
        let source = """
        fun main() {
            val arr = arrayOf(10, 20, 30, 40)
            println(arr.filterIndexed { index, value -> index % 2 == 0 })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayFilterIndexed", expected: "[10, 30]\n")
    }

    func testCodegenArrayMapNotNullDropsNullResults() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3, 4, 5)
            println(arr.mapNotNull { if (it % 2 == 0) it * 10 else null })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayMapNotNull", expected: "[20, 40]\n")
    }

    func testCodegenArrayFilterNotExcludesMatchingElements() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3, 4, 5)
            println(arr.filterNot { it % 2 == 0 })
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayFilterNot", expected: "[1, 3, 5]\n")
    }

    func testCodegenArrayFilterNotNullDropsNullElements() throws {
        let source = """
        fun main() {
            val arr: Array<Int?> = arrayOf(1, null, 2, null, 3)
            println(arr.filterNotNull())
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayFilterNotNull", expected: "[1, 2, 3]\n")
    }

    func testCodegenArrayFirstAndLastZeroArgReturnEndpointsAndThrowWhenEmpty() throws {
        let source = """
        fun main() {
            val arr = arrayOf(5, 10, 15)
            println(arr.first())
            println(arr.last())
            println(arr.firstOrNull())
            println(arr.lastOrNull())

            val empty = emptyArray<Int>()
            println(empty.firstOrNull())
            println(empty.lastOrNull())
            try {
                empty.first()
            } catch (e: NoSuchElementException) {
                println("first-empty: ${e.message}")
            }
            try {
                empty.last()
            } catch (e: NoSuchElementException) {
                println("last-empty: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayFirstLastZeroArg",
            expected:
                """
                5
                15
                5
                15
                null
                null
                first-empty: Array is empty.
                last-empty: Array is empty.
                """
                + "\n"
        )
    }

    func testCodegenArrayFirstAndLastWithPredicateReturnMatchOrThrow() throws {
        let source = """
        fun main() {
            val arr = arrayOf(5, 10, 15, 20)
            println(arr.first { it > 10 })
            println(arr.firstOrNull { it > 100 })
            println(arr.last { it < 20 })
            println(arr.lastOrNull { it > 100 })
            try {
                arr.first { it > 100 }
            } catch (e: NoSuchElementException) {
                println("first-pred: ${e.message}")
            }
            try {
                arr.last { it > 100 }
            } catch (e: NoSuchElementException) {
                println("last-pred: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayFirstLastPredicate",
            expected:
                """
                15
                null
                15
                null
                first-pred: Array contains no element matching the predicate.
                last-pred: Array contains no element matching the predicate.
                """
                + "\n"
        )
    }
}

