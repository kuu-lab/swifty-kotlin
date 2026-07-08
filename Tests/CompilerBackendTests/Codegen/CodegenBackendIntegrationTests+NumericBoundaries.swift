@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testNumericBoundaryUnsignedCompanionConstants() throws {
        let source = """
        fun main() {
            println(UInt.MAX_VALUE)
            println(UInt.MIN_VALUE)
            println(UInt.SIZE_BITS)
            println(UInt.SIZE_BYTES)
            println(ULong.MAX_VALUE)
            println(ULong.MIN_VALUE)
            println(ULong.SIZE_BITS)
            println(ULong.SIZE_BYTES)
            println(UByte.MAX_VALUE)
            println(UByte.MIN_VALUE)
            println(UByte.SIZE_BITS)
            println(UByte.SIZE_BYTES)
            println(UShort.MAX_VALUE)
            println(UShort.MIN_VALUE)
            println(UShort.SIZE_BITS)
            println(UShort.SIZE_BYTES)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryUnsignedConstants",
            expected: """
            4294967295
            0
            32
            4
            18446744073709551615
            0
            64
            8
            255
            0
            8
            1
            65535
            0
            16
            2
            """ + "\n"
        )
    }

    func testNumericBoundaryConversionTruncation() throws {
        let source = """
        fun main() {
            println(200.toByte())
            println(255.toByte())
            println(256.toByte())
            println(1000.toByte())
            println(40000.toShort())
            println(70000.toShort())
            println(65536.toShort())
            println(4294967296L.toInt())
            println(4294967297L.toInt())
            println(Long.MAX_VALUE.toInt())
            println(Long.MIN_VALUE.toInt())
            println((-1).toLong())
            println(Int.MIN_VALUE.toLong())
            val b: Byte = -1
            println(b.toInt())
            val s: Short = -1
            println(s.toInt())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryConversionTruncation",
            expected: """
            -56
            -1
            0
            -24
            -25536
            4464
            0
            0
            1
            -1
            0
            -1
            -2147483648
            -1
            -1
            """ + "\n"
        )
    }

    func testNumericBoundaryFloatToInt() throws {
        let source = """
        fun main() {
            println(Double.NaN.toInt())
            println(Double.POSITIVE_INFINITY.toInt())
            println(Double.NEGATIVE_INFINITY.toInt())
            println(1e20.toInt())
            println((-1e20).toInt())
            println(3.99.toInt())
            println((-3.99).toInt())
            println(Double.NaN.toLong())
            println(Double.POSITIVE_INFINITY.toLong())
            println(Double.NEGATIVE_INFINITY.toLong())
            println(1e30.toLong())
            println((-1e30).toLong())
            println(Float.NaN.toInt())
            println(Float.POSITIVE_INFINITY.toInt())
            println(1e20f.toInt())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryFloatToInt",
            expected: """
            0
            2147483647
            -2147483648
            2147483647
            -2147483648
            3
            -3
            0
            9223372036854775807
            -9223372036854775808
            9223372036854775807
            -9223372036854775808
            0
            2147483647
            2147483647
            """ + "\n"
        )
    }

    func testNumericBoundaryUIntArithmeticWraps() throws {
        let source = """
        fun main() {
            println(UInt.MAX_VALUE + 1u)
            println(0u - 1u)
            println(UInt.MAX_VALUE * 2u)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryUIntOverflow",
            expected: """
            0
            4294967295
            4294967294
            """ + "\n"
        )
    }

    func testNumericBoundaryUnsignedNarrowingConversions() throws {
        let source = """
        fun main() {
            println(UInt.MAX_VALUE.toByte())
            println(UInt.MAX_VALUE.toShort())
            println(ULong.MAX_VALUE.toByte())
            println(ULong.MAX_VALUE.toShort())
            println(UByte.MAX_VALUE.toByte())
            println(UByte.MAX_VALUE.toShort())
            println(UShort.MAX_VALUE.toByte())
            println(UShort.MAX_VALUE.toShort())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryUnsignedNarrowingConversions",
            expected: """
            -1
            -1
            -1
            -1
            -1
            255
            -1
            -1
            """ + "\n"
        )
    }

    func testNumericBoundarySignedUnsignedReinterpretation() throws {
        // Regression for kk_int_to_uint / kk_long_to_uint / kk_uint_to_int /
        // kk_ulong_to_int: these used to be identity functions, so a negative
        // signed source (or an unsigned source >= 2^31) kept its original
        // Int64 payload instead of reinterpreting bits for the target type.
        let source = """
        fun main() {
            val n: Long = -1L
            println(n.toUInt())
            println(n.toUInt() == 4294967295u)
            println((-1).toUInt())
            println((-1).toLong().toUInt())
            println((n and 0xffffffffL).toInt().toUInt())
            println(4294967295u.toInt())
            println(2147483648u.toInt())
            println(4294967296uL.toInt())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundarySignedUnsignedReinterpretation",
            expected: """
            4294967295
            true
            4294967295
            4294967295
            4294967295
            -1
            -2147483648
            0
            """ + "\n"
        )
    }

    func testNumericBoundaryIntToCharTruncates() throws {
        let source = """
        fun main() {
            println(65601.toChar().code)
            println(70000.toChar().code)
            println(65536.toChar().code)
            println(131072.toChar().code)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryIntToChar",
            expected: """
            65
            4464
            0
            0
            """ + "\n"
        )
    }

    func testNumericBoundaryCharArithmeticBasics() throws {
        let source = """
        fun main() {
            println('A'.code)
            println('0'.code)
            println('Z' + 1)
            println('B' - 1)
            println('Z' - 'A')
            println('9' - '0')
            println(65.toChar())
            println(65.toChar().code)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumericBoundaryCharArithmeticBasics",
            expected: """
            65
            48
            [
            A
            25
            9
            A
            65
            """ + "\n"
        )
    }
}

