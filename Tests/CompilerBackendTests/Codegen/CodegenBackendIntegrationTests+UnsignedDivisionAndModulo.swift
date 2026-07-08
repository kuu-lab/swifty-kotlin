@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

/// Regression coverage for KSP-466: `/` and `%` on ULong performed plain signed
/// Int64 division/modulo, which is wrong once a value's high bit is set (any
/// ULong >= 2^63) — e.g. `17663719463477156090uL / 2uL` printed
/// `18055231768593353853` instead of `8831859731738578045`. UInt does not
/// exhibit the bug because it is always zero-extended into the shared 64-bit
/// container. This is the same root-cause family as the ULong comparison/
/// toString sign-misinterpretation bug.
extension CodegenBackendIntegrationTests {
    func testUnsignedDivisionAndModuloHighBitSetULong() throws {
        let source = """
        fun main() {
            val big: ULong = 17663719463477156090uL
            println(big / 2uL)
            println(big % 7uL)
            println(big % 1000uL)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedDivisionAndModuloHighBitSetULong",
            expected: """
            8831859731738578045
            0
            90
            """ + "\n"
        )
    }

    func testUnsignedDivisionAndModuloULongMaxValueBoundary() throws {
        let source = """
        fun main() {
            println(ULong.MAX_VALUE / 1uL)
            println(ULong.MAX_VALUE / ULong.MAX_VALUE)
            println(ULong.MAX_VALUE % ULong.MAX_VALUE)
            val big: ULong = 17663719463477156090uL
            println(ULong.MAX_VALUE / big)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedDivisionAndModuloULongMaxValueBoundary",
            expected: """
            18446744073709551615
            1
            0
            1
            """ + "\n"
        )
    }

    func testUnsignedDivisionAndModuloMemberCallForms() throws {
        // div()/rem()/floorDiv()/mod() are explicit member-call forms of the
        // same operators, lowered through a separate CallLowerer code path
        // (CallLowerer+PrimitiveMemberCalls.swift) that already routed to
        // kk_op_udiv/kk_op_urem before this fix -- lock in that they agree
        // with the infix operators for a high-bit-set value.
        let source = """
        fun main() {
            val big: ULong = 17663719463477156090uL
            println(big.div(2uL))
            println(big.rem(7uL))
            println(big.floorDiv(2uL))
            println(big.mod(7uL))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedDivisionAndModuloMemberCallForms",
            expected: """
            8831859731738578045
            0
            8831859731738578045
            0
            """ + "\n"
        )
    }

    func testUnsignedCompoundAssignDivisionAndModulo() throws {
        let source = """
        fun main() {
            var big: ULong = 17663719463477156090uL
            big /= 2uL
            println(big)
            var big2: ULong = 17663719463477156090uL
            big2 %= 1000uL
            println(big2)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedCompoundAssignDivisionAndModulo",
            expected: """
            8831859731738578045
            90
            """ + "\n"
        )
    }

    func testUnsignedDivisionAndModuloByZeroThrows() throws {
        let source = """
        fun main() {
            val big: ULong = 17663719463477156090uL
            val zero: ULong = 0uL
            try {
                println(big / zero)
            } catch (e: ArithmeticException) {
                println("ulong div: ArithmeticException")
            }
            try {
                println(big % zero)
            } catch (e: ArithmeticException) {
                println("ulong rem: ArithmeticException")
            }
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedDivisionAndModuloByZeroThrows",
            expected: """
            ulong div: ArithmeticException
            ulong rem: ArithmeticException
            """ + "\n"
        )
    }

    func testUnsignedDivisionAndModuloUIntUnaffected() throws {
        // UInt is zero-extended into the shared 64-bit container, so it never
        // exhibited this bug -- this test locks in that the fix leaves it correct.
        let source = """
        fun main() {
            val small: UInt = 17u
            val big: UInt = UInt.MAX_VALUE
            println(big / small)
            println(big % small)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UnsignedDivisionAndModuloUIntUnaffected",
            expected: """
            252645135
            0
            """ + "\n"
        )
    }
}
