@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenIntArithmeticWrapsAt32Bits() throws {
        let source = """
        fun main() {
            println(Int.MAX_VALUE + 1)
            println(Int.MIN_VALUE - 1)
            println(Int.MAX_VALUE * 2)
            println(100000 * 100000)
            println(-Int.MIN_VALUE)
            println(Int.MIN_VALUE / -1)
            println(Int.MIN_VALUE % -1)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "IntOverflowArithmetic",
            expected: """
            -2147483648
            2147483647
            -2
            1410065408
            -2147483648
            -2147483648
            0
            """ + "\n"
        )
    }
    func testCodegenIntArithmeticWrapsForRuntimeValues() throws {
        let source = """
        fun addOne(x: Int): Int = x + 1
        fun square(x: Int): Int = x * x
        fun negate(x: Int): Int = -x

        fun main() {
            println(addOne(Int.MAX_VALUE))
            println(square(100000))
            println(negate(Int.MIN_VALUE))
            var acc = 1
            for (i in 0 until 31) {
                acc *= 2
            }
            println(acc)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "IntOverflowRuntime",
            expected: """
            -2147483648
            1410065408
            -2147483648
            -2147483648
            """ + "\n"
        )
    }
    func testCodegenIntShiftSemantics() throws {
        let source = """
        fun main() {
            println(1 shl 31)
            println(1 shl 32)
            println(1 shl 33)
            println(-1 ushr 28)
            println(-1 ushr 0)
            println(-8 shr 1)
            println(256 shr 4)
            println(Int.MIN_VALUE shr 31)
            println(Int.MIN_VALUE ushr 31)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "IntShiftSemantics",
            expected: """
            -2147483648
            1
            2
            15
            -1
            -4
            16
            -1
            1
            """ + "\n"
        )
    }
    func testCodegenIntBitwiseSemantics() throws {
        let source = """
        fun main() {
            println(0xFF and 0x0F)
            println(0xF0 or 0x0F)
            println(0b1010 xor 0b0110)
            println(0.inv())
            println(255.inv())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "IntBitwiseSemantics",
            expected: """
            15
            255
            12
            -1
            -256
            """ + "\n"
        )
    }
    func testCodegenLongMinValueArithmetic() throws {
        let source = """
        fun main() {
            println(Long.MIN_VALUE)
            var lmin = Long.MIN_VALUE
            println(lmin - 1L)
            println(-lmin)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "LongMinValueArithmetic",
            expected: """
            -9223372036854775808
            9223372036854775807
            -9223372036854775808
            """ + "\n"
        )
    }
    func testCodegenLongArithmeticStays64Bit() throws {
        let source = """
        fun main() {
            println(2147483647L + 1L)
            println(1000000000L * 1000000000L)
            println(1L shl 40)
            println(Long.MAX_VALUE)
            val i = 2000000000
            val l = 3000000000L
            println(i + l)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "LongArithmetic64Bit",
            expected: """
            2147483648
            1000000000000000000
            1099511627776
            9223372036854775807
            5000000000
            """ + "\n"
        )
    }
}

