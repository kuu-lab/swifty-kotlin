@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesArrayEdgeCases() throws {
        let source = """
        @OptIn(ExperimentalUnsignedTypes::class)
        fun main() {
            val empty = emptyArray<Int>()
            println(empty.size)

            val single = arrayOf(7)
            println(single[0])

            val many = arrayOf(1, 2, 3)
            println(many[0])
            println(many[1])
            println(many[2])

            val ints = intArrayOf(4, 5, 6)
            println(ints[1])

            val stringArray = arrayOf("a", "c", "e", "g")
            println(stringArray.binarySearch("c"))
            println(stringArray.binarySearch("d", 1))
            println(stringArray.binarySearch("g", 1, 4))

            println(ints.binarySearch(5))
            println(ints.binarySearch(7, 1))
            println(ints.binarySearch(6, 1, 3))

            val uintArray = uintArrayOf(10u, 20u, 30u, 40u)
            println(uintArray.binarySearch(30u))
            println(uintArray.binarySearch(15u, 1))
            println(uintArray.binarySearch(40u, 1, 4))

            val ulongArray = ulongArrayOf(10uL, 20uL, 30uL, 40uL)
            println(ulongArray.binarySearch(30uL))
            println(ulongArray.binarySearch(15uL, 1))
            println(ulongArray.binarySearch(40uL, 1, 4))

            val boxed: Array<Any> = arrayOf<Any>(1, "two", 3)
            println(boxed[1])

            try {
                println(many[10])
            } catch (e: Throwable) {
                println("oob-get")
            }

            try {
                many[10] = 99
                println("unexpected-set")
            } catch (e: Throwable) {
                println("oob-set")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayEdgeCases",
            expected:
                """
                0
                7
                1
                2
                3
                5
                1
                -3
                3
                1
                -4
                2
                2
                -2
                3
                2
                -2
                3
                two
                oob-get
                oob-set
                """
                + "\n"
        )
    }

    func testCodegenCompilesArrayBinarySearchWithComparator() throws {
        let source = """
        fun main() {
            val values = arrayOf(1, 3, 4, 9)
            val comparator = naturalOrder<Int>()
            println(values.binarySearch(4, comparator, 0, 4))
            println(values.binarySearch(5, comparator, 1, 3))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayBinarySearchComparator",
            expected:
                """
                2
                -4
                """ + "\n"
        )
    }

    func testCodegenCompilesArraySortedArrayWith() throws {
        let source = """
        fun main() {
            val numbers = arrayOf(3, 1, 2)
            println(numbers.sortedArrayWith(naturalOrder()).toList())
            println(numbers.sortedArrayWith(reverseOrder()).toList())
            println(numbers.sortedArrayWith { a, b -> b - a }.toList())

            val words = arrayOf("bbb", "a", "cc")
            println(words.sortedArrayWith(compareBy<String> { it.length }).toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArraySortedArrayWith",
            expected:
                """
                [1, 2, 3]
                [3, 2, 1]
                [3, 2, 1]
                [a, cc, bbb]
                """ + "\n"
        )
    }

    func testCodegenCompilesArrayOfNulls() throws {
        let source = """
        fun main() {
            val values: Array<String?> = arrayOfNulls<String>(3)
            val first: String? = values[0]
            println(values.size)
            println(first == null)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayOfNulls",
            expected:
                """
                3
                true
                """ + "\n"
        )
    }

    func testCodegenArrayFirstNotNullOfOrNullReturnsFirstMatchOrNull() throws {
        let source = """
        fun main() {
            val result: String? = arrayOf(1, 2, 3).firstNotNullOfOrNull { if (it > 1) "hit" else null }
            println(result)
            val missing: String? = arrayOf(1, 3, 5).firstNotNullOfOrNull { if (it % 2 == 0) "even" else null }
            println(missing)
        }
        """

        try assertKotlinOutput(source, moduleName: "ArrayFirstNotNullOfOrNull", expected: "hit\nnull\n")
    }

    // Regression test: `for (x in array)` used to compile but never execute the
    // loop body. The for-loop lowers to the generic kk_range_iterator/hasNext/next
    // runtime protocol (arrays get no compile-time-specific rewrite, unlike
    // List/Set/Map/String), and that runtime fallback didn't recognize
    // RuntimeArrayBox, so kk_range_hasNext always reported false.
    func testCodegenArrayForLoopIteratesAllElements() throws {
        let source = """
        fun main() {
            val bytes = "HI".encodeToByteArray()
            for (b in bytes) {
                println(b.toInt())
            }

            val ints = intArrayOf(10, 20, 30)
            for (i in ints) {
                println(i)
            }

            val strings = arrayOf("a", "b", "c")
            for (s in strings) {
                println(s)
            }

            val chars = charArrayOf('x', 'y', 'z')
            for (c in chars) {
                println(c)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayForLoopIteration",
            expected:
                """
                72
                73
                10
                20
                30
                a
                b
                c
                x
                y
                z
                """ + "\n"
        )
    }

    // Regression test: nesting a for-in loop over an array element that is
    // itself iterated (e.g. `for (row in nested) { for (v in row) { ... } }`)
    // used to skip the inner loop body entirely, even after the outer
    // single-level array iteration above was fixed. The outer loop variable's
    // runtime value is still a valid RuntimeArrayBox, so this exercises that
    // nested arrays and mixed Array/List nesting both iterate correctly.
    func testCodegenNestedArrayForLoopIteratesAllElements() throws {
        let source = """
        fun main() {
            val nested = arrayOf(intArrayOf(1, 2), intArrayOf(3, 4))
            for (row in nested) {
                for (v in row) {
                    print("$v ")
                }
            }
            println()

            val cube = arrayOf(arrayOf(intArrayOf(1, 2), intArrayOf(3, 4)), arrayOf(intArrayOf(5, 6), intArrayOf(7, 8)))
            for (plane in cube) {
                for (row in plane) {
                    for (v in row) {
                        print("$v ")
                    }
                }
            }
            println()

            val listOfArrays = listOf(intArrayOf(9, 10), intArrayOf(11, 12))
            for (row in listOfArrays) {
                for (v in row) {
                    print("$v ")
                }
            }
            println()

            val arrayOfLists = arrayOf(listOf(13, 14), listOf(15, 16))
            for (row in arrayOfLists) {
                for (v in row) {
                    print("$v ")
                }
            }
            println()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NestedArrayForLoopIteration",
            expected: "1 2 3 4 \n"
                + "1 2 3 4 5 6 7 8 \n"
                + "9 10 11 12 \n"
                + "13 14 15 16 \n"
        )
    }
}

