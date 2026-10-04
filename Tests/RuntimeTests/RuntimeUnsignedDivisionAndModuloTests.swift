#if canImport(Testing)
@testable import Runtime
import Testing

/// Regression coverage for KSP-466: kk_op_div/kk_op_mod perform plain signed
/// Int division/modulo, which is correct for Int/Long/UInt (UInt is always
/// zero-extended into the shared 64-bit container) but wrong for ULong once a
/// value's high bit is set (any ULong >= 2^63) — the same root-cause family as
/// the kk_op_lt/le/gt/ge sign-misinterpretation bug fixed for comparisons.
/// kk_op_udiv/kk_op_urem reinterpret both operands via UInt(bitPattern:) and
/// still throw ArithmeticException("/ by zero") via outThrown on zero divisor.
@Suite(.serialized)
struct RuntimeUnsignedDivisionAndModuloTests {
    // 17663719463477156090 as UInt64 == -783024610232395526 as Int64.
    private let highBitSet = Int(bitPattern: 17_663_719_463_477_156_090 as UInt)
    private let small = 5

    // MARK: - kk_op_udiv

    @Test func testUnsignedDivisionUsesFullBitWidth() {
        var outThrown = 0
        let quotient = kk_op_udiv(highBitSet, 2, &outThrown)
        #expect(outThrown == 0)
        #expect(UInt(bitPattern: quotient) == 8_831_859_731_738_578_045)
    }

    @Test func testUnsignedDivisionAgreesWithSignedForSmallValues() {
        var outThrownUnsigned = 0
        var outThrownSigned = 0
        #expect(
            kk_op_udiv(17, 5, &outThrownUnsigned) == kk_op_div(17, 5, &outThrownSigned)
        )
        #expect(outThrownUnsigned == 0)
        #expect(outThrownSigned == 0)
    }

    @Test func testUnsignedDivisionAtMaxValue() {
        var outThrown = 0
        let maxULong = Int(bitPattern: UInt.max)
        let quotient = kk_op_udiv(maxULong, highBitSet, &outThrown)
        #expect(outThrown == 0)
        #expect(UInt(bitPattern: quotient) == 1)
    }

    @Test func testUnsignedDivisionByZeroThrowsArithmeticException() {
        var outThrown = 0
        let result = kk_op_udiv(highBitSet, 0, &outThrown)
        #expect(result == 0)
        #expect(outThrown != 0)
    }

    // MARK: - kk_op_urem

    @Test func testUnsignedRemainderUsesFullBitWidth() {
        var outThrown = 0
        let remainder = kk_op_urem(highBitSet, 1000, &outThrown)
        #expect(outThrown == 0)
        #expect(UInt(bitPattern: remainder) == 90)
    }

    @Test func testUnsignedRemainderMatchesBugReportRepro() {
        // Bug report repro: big % 7uL must be in [0, 6]; the pre-fix signed path
        // produced 18446744073709551614 (UInt64.max - 1), clearly out of range.
        var outThrown = 0
        let remainder = kk_op_urem(highBitSet, 7, &outThrown)
        #expect(outThrown == 0)
        #expect(UInt(bitPattern: remainder) == 0)
    }

    @Test func testUnsignedRemainderAgreesWithSignedForSmallValues() {
        var outThrownUnsigned = 0
        var outThrownSigned = 0
        #expect(
            kk_op_urem(17, 5, &outThrownUnsigned) == kk_op_mod(17, 5, &outThrownSigned)
        )
        #expect(outThrownUnsigned == 0)
        #expect(outThrownSigned == 0)
    }

    @Test func testUnsignedRemainderByZeroThrowsArithmeticException() {
        var outThrown = 0
        let result = kk_op_urem(highBitSet, 0, &outThrown)
        #expect(result == 0)
        #expect(outThrown != 0)
    }

    // MARK: - No INT_MIN/-1 special case for unsigned (unlike kk_op_div/kk_op_mod)

    @Test func testUnsignedDivisionAndModuloAtIntMinBitPattern() {
        // Int.min's bit pattern is 2^63 as ULong -- signed division of Int.min / -1
        // overflows and must special-case, but unsigned division has no such case:
        // 2^63 / (2^64 - 1) is simply 0, and 2^63 % (2^64 - 1) is simply 2^63.
        var outThrownDiv = 0
        var outThrownRem = 0
        let quotient = kk_op_udiv(Int.min, -1, &outThrownDiv)
        let remainder = kk_op_urem(Int.min, -1, &outThrownRem)
        #expect(outThrownDiv == 0)
        #expect(outThrownRem == 0)
        #expect(quotient == 0)
        #expect(UInt(bitPattern: remainder) == UInt(bitPattern: Int.min))
    }
}
#endif
