@testable import Runtime
import XCTest

/// Regression coverage for KSP-466: kk_op_div/kk_op_mod perform plain signed
/// Int division/modulo, which is correct for Int/Long/UInt (UInt is always
/// zero-extended into the shared 64-bit container) but wrong for ULong once a
/// value's high bit is set (any ULong >= 2^63) — the same root-cause family as
/// the kk_op_lt/le/gt/ge sign-misinterpretation bug fixed for comparisons.
/// kk_op_udiv/kk_op_urem reinterpret both operands via UInt(bitPattern:) and
/// still throw ArithmeticException("/ by zero") via outThrown on zero divisor.
final class RuntimeUnsignedDivisionAndModuloTests: XCTestCase {
    // 17663719463477156090 as UInt64 == -783024610232395526 as Int64.
    private let highBitSet = Int(bitPattern: 17_663_719_463_477_156_090 as UInt)
    private let small = 5

    // MARK: - kk_op_udiv

    func testUnsignedDivisionUsesFullBitWidth() {
        var outThrown = 0
        let quotient = kk_op_udiv(highBitSet, 2, &outThrown)
        XCTAssertEqual(outThrown, 0)
        XCTAssertEqual(UInt(bitPattern: quotient), 8_831_859_731_738_578_045)
    }

    func testUnsignedDivisionAgreesWithSignedForSmallValues() {
        var outThrownUnsigned = 0
        var outThrownSigned = 0
        XCTAssertEqual(
            kk_op_udiv(17, 5, &outThrownUnsigned),
            kk_op_div(17, 5, &outThrownSigned)
        )
        XCTAssertEqual(outThrownUnsigned, 0)
        XCTAssertEqual(outThrownSigned, 0)
    }

    func testUnsignedDivisionAtMaxValue() {
        var outThrown = 0
        let maxULong = Int(bitPattern: UInt.max)
        let quotient = kk_op_udiv(maxULong, highBitSet, &outThrown)
        XCTAssertEqual(outThrown, 0)
        XCTAssertEqual(UInt(bitPattern: quotient), 1)
    }

    func testUnsignedDivisionByZeroThrowsArithmeticException() {
        var outThrown = 0
        let result = kk_op_udiv(highBitSet, 0, &outThrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(outThrown, 0)
    }

    // MARK: - kk_op_urem

    func testUnsignedRemainderUsesFullBitWidth() {
        var outThrown = 0
        let remainder = kk_op_urem(highBitSet, 1000, &outThrown)
        XCTAssertEqual(outThrown, 0)
        XCTAssertEqual(UInt(bitPattern: remainder), 90)
    }

    func testUnsignedRemainderMatchesBugReportRepro() {
        // Bug report repro: big % 7uL must be in [0, 6]; the pre-fix signed path
        // produced 18446744073709551614 (UInt64.max - 1), clearly out of range.
        var outThrown = 0
        let remainder = kk_op_urem(highBitSet, 7, &outThrown)
        XCTAssertEqual(outThrown, 0)
        XCTAssertEqual(UInt(bitPattern: remainder), 0)
    }

    func testUnsignedRemainderAgreesWithSignedForSmallValues() {
        var outThrownUnsigned = 0
        var outThrownSigned = 0
        XCTAssertEqual(
            kk_op_urem(17, 5, &outThrownUnsigned),
            kk_op_mod(17, 5, &outThrownSigned)
        )
        XCTAssertEqual(outThrownUnsigned, 0)
        XCTAssertEqual(outThrownSigned, 0)
    }

    func testUnsignedRemainderByZeroThrowsArithmeticException() {
        var outThrown = 0
        let result = kk_op_urem(highBitSet, 0, &outThrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(outThrown, 0)
    }

    // MARK: - No INT_MIN/-1 special case for unsigned (unlike kk_op_div/kk_op_mod)

    func testUnsignedDivisionAndModuloAtIntMinBitPattern() {
        // Int.min's bit pattern is 2^63 as ULong -- signed division of Int.min / -1
        // overflows and must special-case, but unsigned division has no such case:
        // 2^63 / (2^64 - 1) is simply 0, and 2^63 % (2^64 - 1) is simply 2^63.
        var outThrownDiv = 0
        var outThrownRem = 0
        let quotient = kk_op_udiv(Int.min, -1, &outThrownDiv)
        let remainder = kk_op_urem(Int.min, -1, &outThrownRem)
        XCTAssertEqual(outThrownDiv, 0)
        XCTAssertEqual(outThrownRem, 0)
        XCTAssertEqual(quotient, 0)
        XCTAssertEqual(UInt(bitPattern: remainder), UInt(bitPattern: Int.min))
    }
}
