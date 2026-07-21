@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// DEBT-KIR-004 regression coverage: a bitwise-operator right-hand operand
// bound (via a `val`) to the result of a preceding function call must not be
// dropped/read-as-zero. Verified against Kotlin/JVM semantics for each
// operator in both operand orders, plus a self-referential accumulator loop
// matching the pattern Base64.decodeRaw relies on.
extension CodegenBackendIntegrationTests {
    func testCodegenBitwiseOperatorRightOperandFromPrecedingCallIsNotDropped() throws {
        let source = """
        fun main() {
            val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            val value = alphabet.indexOf('Z') // 25, only knowable at runtime

            println(0 or value)
            println(value or 0)
            println(63 and value)
            println(value and 63)
            println(0 xor value)
            println(value xor 0)
            println(1 shl (value and 4))
            println(1024 shr (value and 4))
            println(-1 ushr (value and 4))

            val valueL = value.toLong()
            println(0L or valueL)
            println(valueL or 0L)
            println(63L and valueL)
            println(valueL and 63L)
            println(0L xor valueL)
            println(valueL xor 0L)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "BitwiseOperatorArgumentOrder",
            expected:
                """
                25
                25
                25
                25
                25
                25
                1
                1024
                -1
                25
                25
                25
                25
                25
                25

                """
        )
    }

    func testCodegenBitwiseOrSelfReferentialAccumulatorWithCallDerivedRightOperand() throws {
        // Mirrors Base64.decodeRaw's `buffer = (buffer shl 6) or value` loop:
        // a mutable accumulator combined with a right operand that comes from
        // a preceding function call, decoding "SGVsbG8=" ("Hello") by hand.
        let source = """
        fun main() {
            val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            val source = "SGVsbG8="
            var buffer = 0
            var bitsCollected = 0
            var i = 0
            while (i < source.length) {
                val c = source[i]
                if (c == '=') {
                    i += 1
                    continue
                }
                val value = alphabet.indexOf(c)
                buffer = (buffer shl 6) or value
                bitsCollected += 6
                if (bitsCollected >= 8) {
                    bitsCollected -= 8
                    println((buffer shr bitsCollected) and 0xFF)
                }
                i += 1
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "BitwiseOrAccumulatorLoop",
            expected:
                """
                72
                101
                108
                108
                111

                """
        )
    }
}
