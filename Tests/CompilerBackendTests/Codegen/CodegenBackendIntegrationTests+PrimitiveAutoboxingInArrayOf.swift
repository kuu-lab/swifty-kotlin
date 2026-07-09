@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testPrimitiveArgumentBoxedWhenBuiltWithArrayOf() throws {
        let source = """
        fun main() {
            // Reported bug: arrayOf(...) stored raw elements instead of boxing them,
            // unlike listOf(...)/mutableListOf(...). Both construction (toString) and
            // indexed read-back (arr[i]) must see the concrete boxed type.
            val ints = arrayOf(1, 2, 3)
            println(ints.joinToString())
            println(ints[0])
            println(ints[1])
            println(ints[2])

            val chars = arrayOf('a', 'b', 'c')
            println(chars.joinToString())
            println(chars[1])

            // Boolean elements must render as true/false, not 0/1.
            val bools = arrayOf(true, false)
            println(bools.joinToString())
            println(bools[0])
            println(bools[1])

            // Double elements must render as their value, not the raw bit pattern.
            val doubles = arrayOf(1.5, 2.5)
            println(doubles.joinToString())
            println(doubles[0])
            println(doubles[1])

            // Specialized primitive array factories share arrayOf's "kk_array_of"
            // external link but must keep storing raw values, not boxed ones.
            val ia = intArrayOf(10, 20, 30)
            println(ia.joinToString())
            println(ia[1])

            // Mixed Array<Any> elements.
            val mixed = arrayOf<Any>(1, "two", 3.0, true)
            println(mixed.joinToString())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "PrimitiveAutoboxingInArrayOf",
            expected:
                """
                1, 2, 3
                1
                2
                3
                a, b, c
                b
                true, false
                true
                false
                1.5, 2.5
                1.5
                2.5
                10, 20, 30
                20
                1, two, 3.0, true
                """
                + "\n"
        )
    }

    func testArrayOfElementIsCheckSeesConcreteBoxedType() throws {
        let source = """
        fun describe(x: Any?): String = when (x) {
            is Int -> "Int:$x"
            is Char -> "Char:$x"
            is Boolean -> "Boolean:$x"
            is Double -> "Double:$x"
            is String -> "String:$x"
            else -> "Other"
        }

        fun main() {
            val values = arrayOf<Any>(1, 'a', true, 1.5, "s")
            println(describe(values[0]))
            println(describe(values[1]))
            println(describe(values[2]))
            println(describe(values[3]))
            println(describe(values[4]))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ArrayOfElementIsCheck",
            expected:
                """
                Int:1
                Char:a
                Boolean:true
                Double:1.5
                String:s
                """
                + "\n"
        )
    }

    func testArrayOfIndexedAssignBoxesPrimitiveValue() throws {
        let source = """
        fun main() {
            // arr[i] = value must box a primitive value before storing it, matching
            // how arrayOf(...) boxes elements at construction — otherwise the array
            // ends up with a mix of boxed and raw elements and later reads/toString
            // calls misread the raw slot.
            val doubles = arrayOf(1.5, 2.5, 3.5)
            doubles[1] = 9.5
            println(doubles.joinToString())

            val bools = arrayOf(true, false, true)
            bools[0] = false
            println(bools.joinToString())

            val ints = arrayOf(1, 2, 3)
            ints[2] = 42
            println(ints.joinToString())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ArrayOfIndexedAssignBoxing",
            expected:
                """
                1.5, 9.5, 3.5
                false, false, true
                1, 2, 42
                """
                + "\n"
        )
    }
}
