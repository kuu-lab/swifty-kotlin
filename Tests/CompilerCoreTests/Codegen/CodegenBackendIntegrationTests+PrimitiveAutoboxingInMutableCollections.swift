@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testPrimitiveArgumentBoxedWhenAddedToMutableCollections() throws {
        let source = """
        fun main() {
            // Reported bug: literal-built list seeds boxed Chars, add('d') must match.
            val chars = mutableListOf('a', 'b', 'c')
            chars.add('d')
            println(chars)

            // Generalization: an empty MutableList<Char>.
            val fresh = mutableListOf<Char>()
            fresh.add('x')
            fresh.add('y')
            println(fresh)

            // add(index, element) insertion.
            val ins = mutableListOf('a', 'c')
            ins.add(1, 'b')
            println(ins)

            // set(index, element) via indexed assignment.
            val seq = mutableListOf('a', 'b', 'c')
            seq[1] = 'z'
            println(seq)

            // MutableSet.add(Char).
            val set = mutableSetOf<Char>()
            set.add('m')
            println(set)

            // Boolean elements must render as true/false, not 0/1.
            val flags = mutableListOf<Boolean>()
            flags.add(true)
            flags.add(false)
            println(flags)

            // Double elements must render as their value, not the raw bit pattern.
            val reals = mutableListOf<Double>()
            reals.add(1.5)
            println(reals)

            // Regression: Int elements still render as their decimal value.
            val nums = mutableListOf<Int>()
            nums.add(100)
            println(nums)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "PrimitiveAutoboxingInMutableCollections",
            expected:
                """
                [a, b, c, d]
                [x, y]
                [a, b, c]
                [a, z, c]
                [m]
                [true, false]
                [1.5]
                [100]
                """
                + "\n"
        )
    }
}

