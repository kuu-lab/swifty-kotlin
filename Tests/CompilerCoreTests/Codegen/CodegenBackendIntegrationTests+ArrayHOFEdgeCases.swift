@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenArrayMapAndFilter() throws {
        // map/filter results are used via direct chaining to avoid the listExprIDs
        // variable-reference tracking limitation (intermediate variables lose list tracking).
        let source = """
        fun main() {
            val nums = arrayOf(1, 2, 3, 4, 5)

            nums.map { it * 2 }.forEach { println(it) }

            nums.filter { it % 2 == 0 }.forEach { println(it) }

            println(nums.filter { it > 10 }.isEmpty())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayMapFilter",
            expected:
                """
                2
                4
                6
                8
                10
                2
                4
                true
                """
                + "\n"
        )
    }

    func testCodegenArrayForEach() throws {
        let source = """
        fun main() {
            val nums = arrayOf(10, 20, 30)
            nums.forEach { println(it) }
            val empty = emptyArray<Int>()
            empty.forEach { println("unreachable") }
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayForEach",
            expected:
                """
                10
                20
                30
                done
                """
                + "\n"
        )
    }

    func testCodegenArrayFoldAndReduce() throws {
        let source = """
        fun main() {
            val nums = arrayOf(1, 2, 3, 4, 5)

            val sum = nums.fold(0) { acc, v -> acc + v }
            println(sum)

            val product = nums.reduce { a, b -> a * b }
            println(product)

            val concat = arrayOf("a", "b", "c").fold("") { acc, v -> acc + v }
            println(concat)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayFoldReduce",
            expected:
                """
                15
                120
                abc
                """
                + "\n"
        )
    }

    func testCodegenArrayFindAndFindLast() throws {
        let source = """
        fun main() {
            val nums = arrayOf(1, 2, 3, 4, 5)

            val found = nums.find { it > 3 }
            println(found != null)
            println(found)

            val notFound = nums.find { it > 10 }
            println(notFound == null)

            val lastEven = nums.findLast { it % 2 == 0 }
            println(lastEven)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayFind",
            expected:
                """
                true
                4
                true
                4
                """
                + "\n"
        )
    }

    func testCodegenArrayAnyAllNoneCount() throws {
        let source = """
        fun main() {
            val nums = arrayOf(1, 2, 3, 4, 5)

            println(nums.any { it > 4 })
            println(nums.any { it > 10 })

            println(nums.all { it > 0 })
            println(nums.all { it > 3 })

            println(nums.none { it < 0 })
            println(nums.none { it > 0 })

            println(nums.count { it % 2 == 0 })
            println(nums.count { it > 10 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayAnyAllNone",
            expected:
                """
                true
                false
                true
                false
                true
                false
                2
                0
                """
                + "\n"
        )
    }

    func testCodegenArrayCopyOfRangeBoundaryThrows() throws {
        let source = """
        fun main() {
            val nums = arrayOf(1, 2, 3, 4, 5)

            val slice = nums.copyOfRange(1, 4)
            println(slice.size)
            println(slice[0])
            println(slice[2])

            try {
                nums.copyOfRange(3, 1)
                println("no-throw")
            } catch (e: Throwable) {
                println("fromIndex-gt-toIndex")
            }

            try {
                nums.copyOfRange(-1, 2)
                println("no-throw")
            } catch (e: Throwable) {
                println("negative-fromIndex")
            }

            try {
                nums.copyOfRange(0, 10)
                println("no-throw")
            } catch (e: Throwable) {
                println("toIndex-out-of-bounds")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayCopyOfRangeBoundary",
            expected:
                """
                3
                2
                4
                fromIndex-gt-toIndex
                negative-fromIndex
                toIndex-out-of-bounds
                """
                + "\n"
        )
    }
}

