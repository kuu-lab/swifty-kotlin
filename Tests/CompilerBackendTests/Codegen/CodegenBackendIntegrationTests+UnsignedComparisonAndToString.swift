@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

/// Regression coverage for a ULong sign-misinterpretation bug found while
/// working on KSP-466 (kotlin.random.Random.nextULong()): any ULong with the
/// high bit set (>= 2^63) was compared and stringified as if it were a
/// signed Int64, e.g. `17663719463477156090uL >= 0uL` returned `false` and
/// `.toString()` printed the negative signed reinterpretation (or, at the
/// 2^63 boundary, the literal string "null"). UInt does not exhibit the bug
/// because it is always zero-extended into the shared 64-bit container.
extension CodegenBackendIntegrationTests {
    func testUnsignedComparisonHighBitSetULong() throws {
        let source = """
        fun main() {
            val small: ULong = 5uL
            val big: ULong = 17663719463477156090uL
            println(small >= 0uL)
            println(big >= 0uL)
            println(big > small)
            println(big >= small)
            println(small < big)
            println(small <= big)
            println(big < small)
            println(big <= small)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedComparisonHighBitSetULong",
            expected: """
            true
            true
            true
            true
            true
            true
            false
            false
            """ + "\n"
        )
    }

    func testUnsignedComparisonULongMaxValueBoundary() throws {
        let source = """
        fun main() {
            println(ULong.MAX_VALUE >= 0uL)
            println(ULong.MAX_VALUE > 0uL)
            println(0uL < ULong.MAX_VALUE)
            println(ULong.MAX_VALUE >= ULong.MAX_VALUE)
            println(ULong.MAX_VALUE <= ULong.MAX_VALUE)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedComparisonULongMaxValueBoundary",
            expected: """
            true
            true
            true
            true
            true
            """ + "\n"
        )
    }

    func testUnsignedToStringHighBitSetULong() throws {
        let source = """
        fun main() {
            val big: ULong = 17663719463477156090uL
            println(big.toString())
            println(ULong.MAX_VALUE.toString())
            // 2^63 shares its raw bit pattern with the compiler's null
            // sentinel (Int.min); toString() must still render the real
            // unsigned value rather than the literal string "null".
            val boundary: ULong = 9223372036854775808uL
            println(boundary.toString())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedToStringHighBitSetULong",
            expected: """
            17663719463477156090
            18446744073709551615
            9223372036854775808
            """ + "\n"
        )
    }

    func testUnsignedStringTemplateHighBitSetULong() throws {
        let source = """
        fun main() {
            val big: ULong = 17663719463477156090uL
            println("value=$big")
            println("concat=" + big)

            val nullableBig: ULong? = big
            println("nullable=$nullableBig")
            val nullableNone: ULong? = null
            println("isNull=$nullableNone")
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedStringTemplateHighBitSetULong",
            expected: """
            value=17663719463477156090
            concat=17663719463477156090
            nullable=17663719463477156090
            isNull=null
            """ + "\n"
        )
    }

    func testUnsignedComparisonAndToStringUIntUnaffected() throws {
        // UInt is zero-extended into the shared 64-bit container, so it never
        // exhibited this bug — this test locks in that the fix leaves it correct.
        let source = """
        fun main() {
            val small: UInt = 5u
            val big: UInt = UInt.MAX_VALUE
            println(small >= 0u)
            println(big >= 0u)
            println(big > small)
            println(big.toString())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedComparisonAndToStringUIntUnaffected",
            expected: """
            true
            true
            true
            4294967295
            """ + "\n"
        )
    }
}
