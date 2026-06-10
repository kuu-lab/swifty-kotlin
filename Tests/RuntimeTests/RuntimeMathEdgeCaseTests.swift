@testable import Runtime
import XCTest

/// STDLIB-MATH-003: kotlin.math runtime / ABI boundary value and edge case coverage.
///
/// This file tests IEEE 754 special inputs (NaN, ±Infinity, ±0.0, subnormals)
/// and saturation / overflow behaviour for every kotlin.math entry point that
/// is not already exhaustively exercised in RuntimeMathTests.swift.
final class RuntimeMathEdgeCaseTests: XCTestCase {

    // MARK: - Helpers

    private func doubleToBits(_ value: Double) -> Int {
        Int(truncatingIfNeeded: value.bitPattern)
    }

    private func doubleFromBits(_ raw: Int) -> Double {
        Double(bitPattern: UInt64(bitPattern: Int64(raw)))
    }

    private func floatToBits(_ value: Float) -> Int {
        Int(value.bitPattern)
    }

    private func floatFromBits(_ raw: Int) -> Float {
        Float(bitPattern: UInt32(truncatingIfNeeded: raw))
    }

    // MARK: - abs(Double) IEEE 754 edge cases

    func testAbsDoublePositiveZero() {
        // abs(+0.0) == +0.0
        let result = doubleFromBits(kk_math_abs(doubleToBits(0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertFalse(result.sign == .minus)
    }

    func testAbsDoubleNegativeZero() {
        // abs(-0.0) == +0.0 (sign bit cleared)
        let result = doubleFromBits(kk_math_abs(doubleToBits(-0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertFalse(result.sign == .minus)
    }

    func testAbsDoublePositiveInfinity() {
        let result = doubleFromBits(kk_math_abs(doubleToBits(Double.infinity)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    func testAbsDoubleNegativeInfinity() {
        // abs(-Inf) == +Inf
        let result = doubleFromBits(kk_math_abs(doubleToBits(-Double.infinity)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    func testAbsDoubleSubnormal() {
        // abs of smallest subnormal should stay subnormal with same magnitude
        let sub = Double.leastNonzeroMagnitude
        XCTAssertEqual(doubleFromBits(kk_math_abs(doubleToBits(-sub))), sub)
    }

    // MARK: - abs(Float) IEEE 754 edge cases

    func testAbsFloatNegativeZero() {
        let result = floatFromBits(kk_math_abs_float(floatToBits(-0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertFalse(result.sign == .minus)
    }

    func testAbsFloatInfinity() {
        XCTAssertTrue(floatFromBits(kk_math_abs_float(floatToBits(Float.infinity))).isInfinite)
        XCTAssertTrue(floatFromBits(kk_math_abs_float(floatToBits(-Float.infinity))).isInfinite)
        XCTAssertGreaterThan(floatFromBits(kk_math_abs_float(floatToBits(-Float.infinity))), 0)
    }

    func testAbsFloatSubnormal() {
        let sub = Float.leastNonzeroMagnitude
        XCTAssertEqual(floatFromBits(kk_math_abs_float(floatToBits(-sub))), sub)
    }

    // MARK: - abs(Long) overflow

    func testAbsLongMinValue() {
        // abs(Long.MIN_VALUE) overflows and stays Long.MIN_VALUE (Kotlin spec)
        XCTAssertEqual(kk_math_abs_long(Int(truncatingIfNeeded: Int64.min)), Int(truncatingIfNeeded: Int64.min))
    }

    func testAbsLongPositive() {
        XCTAssertEqual(kk_math_abs_long(42), 42)
    }

    func testAbsLongNegative() {
        XCTAssertEqual(kk_math_abs_long(-42), 42)
    }

    // MARK: - sqrt(Double) IEEE 754 edge cases

    func testSqrtDoubleZero() {
        XCTAssertEqual(doubleFromBits(kk_math_sqrt(doubleToBits(0.0))), 0.0)
    }

    func testSqrtDoubleNegativeZero() {
        // sqrt(-0.0) == -0.0 (IEEE 754)
        let result = doubleFromBits(kk_math_sqrt(doubleToBits(-0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertTrue(result.sign == .minus)
    }

    func testSqrtDoubleInfinity() {
        // sqrt(+Inf) == +Inf
        let result = doubleFromBits(kk_math_sqrt(doubleToBits(Double.infinity)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    func testSqrtDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_sqrt(doubleToBits(Double.nan))).isNaN)
    }

    func testSqrtDoubleNegative() {
        // sqrt of a negative number is NaN
        XCTAssertTrue(doubleFromBits(kk_math_sqrt(doubleToBits(-1.0))).isNaN)
    }

    // MARK: - sqrt(Float) IEEE 754 edge cases

    func testSqrtFloatZero() {
        XCTAssertEqual(floatFromBits(kk_math_sqrt_float(floatToBits(0.0))), 0.0)
    }

    func testSqrtFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_sqrt_float(floatToBits(Float.nan))).isNaN)
    }

    func testSqrtFloatNegative() {
        XCTAssertTrue(floatFromBits(kk_math_sqrt_float(floatToBits(-1.0))).isNaN)
    }

    func testSqrtFloatInfinity() {
        let result = floatFromBits(kk_math_sqrt_float(floatToBits(Float.infinity)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    // MARK: - pow(Double) special cases

    func testPowDoubleNaNBase() {
        XCTAssertTrue(doubleFromBits(kk_math_pow(doubleToBits(Double.nan), doubleToBits(2.0))).isNaN)
    }

    func testPowDoubleNaNExp() {
        XCTAssertTrue(doubleFromBits(kk_math_pow(doubleToBits(2.0), doubleToBits(Double.nan))).isNaN)
    }

    func testPowDoubleZeroExponent() {
        // x^0 == 1 for any x (including NaN, Inf)
        XCTAssertEqual(doubleFromBits(kk_math_pow(doubleToBits(Double.nan), doubleToBits(0.0))), 1.0)
        XCTAssertEqual(doubleFromBits(kk_math_pow(doubleToBits(Double.infinity), doubleToBits(0.0))), 1.0)
        XCTAssertEqual(doubleFromBits(kk_math_pow(doubleToBits(0.0), doubleToBits(0.0))), 1.0)
    }

    func testPowDoubleInfinityBase() {
        // Inf^2 == Inf; Inf^(-1) == 0
        let infSquared = doubleFromBits(kk_math_pow(doubleToBits(Double.infinity), doubleToBits(2.0)))
        XCTAssertTrue(infSquared.isInfinite)
        let infToMinusOne = doubleFromBits(kk_math_pow(doubleToBits(Double.infinity), doubleToBits(-1.0)))
        XCTAssertEqual(infToMinusOne, 0.0)
    }

    func testPowDoubleOneBase() {
        // 1^anything == 1 (including NaN exponent by IEEE 754)
        XCTAssertEqual(doubleFromBits(kk_math_pow(doubleToBits(1.0), doubleToBits(Double.nan))), 1.0)
        XCTAssertEqual(doubleFromBits(kk_math_pow(doubleToBits(1.0), doubleToBits(Double.infinity))), 1.0)
    }

    func testPowFloatAndIntOverloads() {
        XCTAssertEqual(floatFromBits(kk_math_pow_float(floatToBits(2.0), floatToBits(3.0))), 8.0, accuracy: 1e-6)
        XCTAssertEqual(doubleFromBits(kk_math_pow_int(doubleToBits(2.0), 3)), 8.0, accuracy: 1e-12)
        XCTAssertEqual(floatFromBits(kk_math_pow_float_int(floatToBits(2.0), 3)), 8.0, accuracy: 1e-6)
        XCTAssertTrue(floatFromBits(kk_math_pow_float(floatToBits(Float.nan), floatToBits(2.0))).isNaN)
    }

    // MARK: - ceil / floor / truncate with special values

    func testCeilDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_ceil(doubleToBits(Double.nan))).isNaN)
    }

    func testCeilDoubleInfinity() {
        XCTAssertTrue(doubleFromBits(kk_math_ceil(doubleToBits(Double.infinity))).isInfinite)
        XCTAssertTrue(doubleFromBits(kk_math_ceil(doubleToBits(-Double.infinity))).isInfinite)
    }

    func testCeilDoubleNegativeZero() {
        // ceil(-0.0) == -0.0
        let result = doubleFromBits(kk_math_ceil(doubleToBits(-0.0)))
        XCTAssertEqual(result, 0.0)
    }

    func testFloorDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_floor(doubleToBits(Double.nan))).isNaN)
    }

    func testFloorDoubleInfinity() {
        XCTAssertTrue(doubleFromBits(kk_math_floor(doubleToBits(Double.infinity))).isInfinite)
        XCTAssertTrue(doubleFromBits(kk_math_floor(doubleToBits(-Double.infinity))).isInfinite)
    }

    func testFloorDoubleNegativeZero() {
        // floor(-0.0) == -0.0 (IEEE 754 符号保持)
        let result = doubleFromBits(kk_math_floor(doubleToBits(-0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertTrue(result.sign == .minus)
    }

    func testTruncateDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_truncate(doubleToBits(Double.nan))).isNaN)
    }

    func testTruncateDoubleInfinity() {
        XCTAssertTrue(doubleFromBits(kk_math_truncate(doubleToBits(Double.infinity))).isInfinite)
        XCTAssertTrue(doubleFromBits(kk_math_truncate(doubleToBits(-Double.infinity))).isInfinite)
    }

    func testTruncateDoubleRoundsTowardZero() {
        XCTAssertEqual(doubleFromBits(kk_math_truncate(doubleToBits(2.9))), 2.0)
        XCTAssertEqual(doubleFromBits(kk_math_truncate(doubleToBits(-2.9))), -2.0)
    }

    func testTruncateFloatRoundsTowardZero() {
        XCTAssertEqual(floatFromBits(kk_math_truncate_float(floatToBits(2.9))), 2.0)
        XCTAssertEqual(floatFromBits(kk_math_truncate_float(floatToBits(-2.9))), -2.0)
    }

    func testTruncateFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_truncate_float(floatToBits(Float.nan))).isNaN)
    }

    func testTruncateDoubleNegativeZero() {
        // truncate(-0.0) == -0.0 (IEEE 754 符号保持)
        let result = doubleFromBits(kk_math_truncate(doubleToBits(-0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertTrue(result.sign == .minus)
    }

    func testTruncateDoublePositiveZeroSign() {
        // truncate(+0.0) == +0.0 (符号保持; -0.0 と対称)
        let result = doubleFromBits(kk_math_truncate(doubleToBits(0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertFalse(result.sign == .minus)
    }

    func testTruncateFloatNegativeZero() {
        let result = floatFromBits(kk_math_truncate_float(floatToBits(-0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertTrue(result.sign == .minus)
    }

    // MARK: - ceil / floor Float special values

    func testCeilFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_ceil_float(floatToBits(Float.nan))).isNaN)
    }

    func testCeilFloatInfinity() {
        XCTAssertTrue(floatFromBits(kk_math_ceil_float(floatToBits(Float.infinity))).isInfinite)
        XCTAssertTrue(floatFromBits(kk_math_ceil_float(floatToBits(-Float.infinity))).isInfinite)
    }

    func testFloorFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_floor_float(floatToBits(Float.nan))).isNaN)
    }

    func testFloorFloatInfinity() {
        XCTAssertTrue(floatFromBits(kk_math_floor_float(floatToBits(Float.infinity))).isInfinite)
        XCTAssertTrue(floatFromBits(kk_math_floor_float(floatToBits(-Float.infinity))).isInfinite)
    }

    func testFloorFloatNegativeZero() {
        let result = floatFromBits(kk_math_floor_float(floatToBits(-0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertTrue(result.sign == .minus)
    }

    // MARK: - round(Double) special values

    func testRoundDoubleInfinity() {
        XCTAssertTrue(doubleFromBits(kk_math_round(doubleToBits(Double.infinity))).isInfinite)
        XCTAssertTrue(doubleFromBits(kk_math_round(doubleToBits(-Double.infinity))).isInfinite)
    }

    func testRoundDoubleNegativeZero() {
        let result = doubleFromBits(kk_math_round(doubleToBits(-0.0)))
        XCTAssertEqual(result, 0.0)
    }

    // MARK: - round(Float) special values

    func testRoundFloatInfinity() {
        XCTAssertTrue(floatFromBits(kk_math_round_float(floatToBits(Float.infinity))).isInfinite)
        XCTAssertTrue(floatFromBits(kk_math_round_float(floatToBits(-Float.infinity))).isInfinite)
    }

    // MARK: - sign(Double) edge cases

    func testSignDoubleNegativeZero() {
        // Kotlin: sign(-0.0) == -0.0
        let result = doubleFromBits(kk_math_sign(doubleToBits(-0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertTrue(result.sign == .minus)
    }

    func testSignDoublePositiveInfinity() {
        XCTAssertEqual(doubleFromBits(kk_math_sign(doubleToBits(Double.infinity))), 1.0)
    }

    func testSignDoubleNegativeInfinity() {
        XCTAssertEqual(doubleFromBits(kk_math_sign(doubleToBits(-Double.infinity))), -1.0)
    }

    func testSignDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_sign(doubleToBits(Double.nan))).isNaN)
    }

    func testSignDoublePositiveZero() {
        // sign(+0.0) == +0.0 (符号保持; -0.0 と対称)
        let result = doubleFromBits(kk_math_sign(doubleToBits(0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertFalse(result.sign == .minus)
    }

    // MARK: - sign(Float) edge cases

    func testSignFloatNegativeZero() {
        let result = floatFromBits(kk_math_sign_float(floatToBits(-0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertTrue(result.sign == .minus)
    }

    func testSignFloatPositiveInfinity() {
        XCTAssertEqual(floatFromBits(kk_math_sign_float(floatToBits(Float.infinity))), 1.0)
    }

    func testSignFloatNegativeInfinity() {
        XCTAssertEqual(floatFromBits(kk_math_sign_float(floatToBits(-Float.infinity))), -1.0)
    }

    func testSignFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_sign_float(floatToBits(Float.nan))).isNaN)
    }

    func testSignFloatPositiveZero() {
        let result = floatFromBits(kk_math_sign_float(floatToBits(0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertFalse(result.sign == .minus)
    }

    // MARK: - hypot(Double) special cases

    func testHypotDoubleInfinity() {
        // hypot(Inf, NaN) == Inf (IEEE 754 mandates this)
        let result = doubleFromBits(kk_math_hypot(doubleToBits(Double.infinity), doubleToBits(Double.nan)))
        XCTAssertTrue(result.isInfinite)
    }

    func testHypotDoubleBothInfinity() {
        let result = doubleFromBits(kk_math_hypot(doubleToBits(Double.infinity), doubleToBits(Double.infinity)))
        XCTAssertTrue(result.isInfinite)
    }

    func testHypotDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_hypot(doubleToBits(Double.nan), doubleToBits(0.0))).isNaN)
    }

    func testHypotDoubleZeros() {
        XCTAssertEqual(doubleFromBits(kk_math_hypot(doubleToBits(0.0), doubleToBits(0.0))), 0.0)
    }

    // MARK: - hypot(Float) special cases

    func testHypotFloatInfinity() {
        let result = floatFromBits(kk_math_hypot_float(floatToBits(Float.infinity), floatToBits(Float.nan)))
        XCTAssertTrue(result.isInfinite)
    }

    func testHypotFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_hypot_float(floatToBits(Float.nan), floatToBits(0.0))).isNaN)
    }

    // MARK: - exp(Double) edge cases

    func testExpDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_exp(doubleToBits(Double.nan))).isNaN)
    }

    func testExpDoublePositiveInfinity() {
        XCTAssertTrue(doubleFromBits(kk_math_exp(doubleToBits(Double.infinity))).isInfinite)
    }

    func testExpDoubleNegativeInfinity() {
        // exp(-Inf) == 0
        XCTAssertEqual(doubleFromBits(kk_math_exp(doubleToBits(-Double.infinity))), 0.0)
    }

    // MARK: - exp(Float) edge cases

    func testExpFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_exp_float(floatToBits(Float.nan))).isNaN)
    }

    func testExpFloatPositiveInfinity() {
        XCTAssertTrue(floatFromBits(kk_math_exp_float(floatToBits(Float.infinity))).isInfinite)
    }

    func testExpFloatNegativeInfinity() {
        XCTAssertEqual(floatFromBits(kk_math_exp_float(floatToBits(-Float.infinity))), 0.0)
    }

    // MARK: - ln(Double) edge cases

    func testLnDoubleZero() {
        // ln(0) == -Inf
        let result = doubleFromBits(kk_math_ln(doubleToBits(0.0)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertLessThan(result, 0)
    }

    func testLnDoubleNegative() {
        XCTAssertTrue(doubleFromBits(kk_math_ln(doubleToBits(-1.0))).isNaN)
    }

    func testLnDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_ln(doubleToBits(Double.nan))).isNaN)
    }

    func testLnDoubleInfinity() {
        XCTAssertTrue(doubleFromBits(kk_math_ln(doubleToBits(Double.infinity))).isInfinite)
        XCTAssertGreaterThan(doubleFromBits(kk_math_ln(doubleToBits(Double.infinity))), 0)
    }

    // MARK: - ln(Float) edge cases

    func testLnFloatZero() {
        let result = floatFromBits(kk_math_ln_float(floatToBits(0.0)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertLessThan(result, 0)
    }

    func testLnFloatNegative() {
        XCTAssertTrue(floatFromBits(kk_math_ln_float(floatToBits(-1.0))).isNaN)
    }

    func testLnFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_ln_float(floatToBits(Float.nan))).isNaN)
    }

    // MARK: - log2 / log10 edge cases (Double)

    func testLog2DoubleOne() {
        XCTAssertEqual(doubleFromBits(kk_math_log2(doubleToBits(1.0))), 0.0)
    }

    func testLog2DoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_log2(doubleToBits(Double.nan))).isNaN)
    }

    func testLog10DoubleOne() {
        XCTAssertEqual(doubleFromBits(kk_math_log10(doubleToBits(1.0))), 0.0)
    }

    func testLog10DoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_log10(doubleToBits(Double.nan))).isNaN)
    }

    // MARK: - log2 / log10 additional domain edge cases (Double)

    func testLog2DoubleZero() {
        // log2(0) == -Inf  (IEEE 754: log of zero is -Inf)
        let result = doubleFromBits(kk_math_log2(doubleToBits(0.0)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertLessThan(result, 0)
    }

    func testLog2DoubleNegative() {
        // log2 of a negative number is NaN
        XCTAssertTrue(doubleFromBits(kk_math_log2(doubleToBits(-1.0))).isNaN)
    }

    func testLog2DoublePositiveInfinity() {
        // log2(+Inf) == +Inf
        let result = doubleFromBits(kk_math_log2(doubleToBits(Double.infinity)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    func testLog10DoubleZero() {
        // log10(0) == -Inf
        let result = doubleFromBits(kk_math_log10(doubleToBits(0.0)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertLessThan(result, 0)
    }

    func testLog10DoubleNegative() {
        // log10 of a negative number is NaN
        XCTAssertTrue(doubleFromBits(kk_math_log10(doubleToBits(-1.0))).isNaN)
    }

    func testLog10DoublePositiveInfinity() {
        // log10(+Inf) == +Inf
        let result = doubleFromBits(kk_math_log10(doubleToBits(Double.infinity)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    // MARK: - log2 / log10 edge cases (Float)

    func testLog2FloatOne() {
        XCTAssertEqual(floatFromBits(kk_math_log2_float(floatToBits(1.0))), 0.0)
    }

    func testLog10FloatOne() {
        XCTAssertEqual(floatFromBits(kk_math_log10_float(floatToBits(1.0))), 0.0)
    }

    // MARK: - log2 / log10 additional domain edge cases (Float)

    func testLog2FloatZero() {
        // log2(0.0f) == -Inf
        let result = floatFromBits(kk_math_log2_float(floatToBits(0.0)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertLessThan(result, 0)
    }

    func testLog2FloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_log2_float(floatToBits(Float.nan))).isNaN)
    }

    func testLog2FloatNegative() {
        // log2 of a negative Float is NaN
        XCTAssertTrue(floatFromBits(kk_math_log2_float(floatToBits(-1.0))).isNaN)
    }

    func testLog2FloatPositiveInfinity() {
        // log2(+Inf) == +Inf
        let result = floatFromBits(kk_math_log2_float(floatToBits(Float.infinity)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    func testLog10FloatZero() {
        // log10(0.0f) == -Inf
        let result = floatFromBits(kk_math_log10_float(floatToBits(0.0)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertLessThan(result, 0)
    }

    func testLog10FloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_log10_float(floatToBits(Float.nan))).isNaN)
    }

    func testLog10FloatNegative() {
        // log10 of a negative Float is NaN
        XCTAssertTrue(floatFromBits(kk_math_log10_float(floatToBits(-1.0))).isNaN)
    }

    func testLog10FloatPositiveInfinity() {
        // log10(+Inf) == +Inf
        let result = floatFromBits(kk_math_log10_float(floatToBits(Float.infinity)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    // MARK: - log(x, base) domain edge cases (Double)
    // Implementation: ln(rawX) / ln(rawBase), so IEEE 754 rules apply directly.

    func testLogDoubleNegativeX() {
        // ln of a negative number is NaN; NaN / finite == NaN
        XCTAssertTrue(doubleFromBits(kk_math_log(doubleToBits(-1.0), doubleToBits(2.0))).isNaN)
    }

    func testLogDoubleZeroX() {
        // ln(0) == -Inf; -Inf / positive_finite == -Inf
        let result = doubleFromBits(kk_math_log(doubleToBits(0.0), doubleToBits(2.0)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertLessThan(result, 0)
    }

    func testLogDoubleNegativeBase() {
        // ln of a negative base is NaN; finite / NaN == NaN
        XCTAssertTrue(doubleFromBits(kk_math_log(doubleToBits(4.0), doubleToBits(-2.0))).isNaN)
    }

    func testLogDoubleBaseOneXEqualsOne() {
        // ln(1) / ln(1) == 0.0 / 0.0 == NaN
        XCTAssertTrue(doubleFromBits(kk_math_log(doubleToBits(1.0), doubleToBits(1.0))).isNaN)
    }

    func testLogDoubleBaseOneXGreaterThanOne() {
        // ln(2) / ln(1) == positive / 0.0 == +Inf  (IEEE 754 nonzero/zero)
        let result = doubleFromBits(kk_math_log(doubleToBits(2.0), doubleToBits(1.0)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    func testLogDoublePositiveInfinityX() {
        // ln(+Inf) / ln(2) == +Inf / positive_finite == +Inf
        let result = doubleFromBits(kk_math_log(doubleToBits(Double.infinity), doubleToBits(2.0)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    func testLogDoubleNaNX() {
        XCTAssertTrue(doubleFromBits(kk_math_log(doubleToBits(Double.nan), doubleToBits(2.0))).isNaN)
    }

    func testLogDoubleNaNBase() {
        XCTAssertTrue(doubleFromBits(kk_math_log(doubleToBits(4.0), doubleToBits(Double.nan))).isNaN)
    }

    // MARK: - log(x, base) domain edge cases (Float)

    func testLogFloatNegativeX() {
        XCTAssertTrue(floatFromBits(kk_math_log_float(floatToBits(-1.0), floatToBits(2.0))).isNaN)
    }

    func testLogFloatZeroX() {
        // ln(0.0f) / ln(2.0f) == -Inf
        let result = floatFromBits(kk_math_log_float(floatToBits(0.0), floatToBits(2.0)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertLessThan(result, 0)
    }

    func testLogFloatNegativeBase() {
        XCTAssertTrue(floatFromBits(kk_math_log_float(floatToBits(4.0), floatToBits(-2.0))).isNaN)
    }

    func testLogFloatBaseOneXEqualsOne() {
        // 0.0f / 0.0f == NaN
        XCTAssertTrue(floatFromBits(kk_math_log_float(floatToBits(1.0), floatToBits(1.0))).isNaN)
    }

    func testLogFloatBaseOneXGreaterThanOne() {
        // positive_finite / 0.0f == +Inf
        let result = floatFromBits(kk_math_log_float(floatToBits(2.0), floatToBits(1.0)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    func testLogFloatPositiveInfinityX() {
        let result = floatFromBits(kk_math_log_float(floatToBits(Float.infinity), floatToBits(2.0)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    func testLogFloatNaNX() {
        XCTAssertTrue(floatFromBits(kk_math_log_float(floatToBits(Float.nan), floatToBits(2.0))).isNaN)
    }

    // MARK: - Double trig NaN / Inf propagation

    func testSinDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_sin(doubleToBits(Double.nan))).isNaN)
    }

    func testSinDoubleInfinity() {
        // sin(Inf) is undefined, should be NaN
        XCTAssertTrue(doubleFromBits(kk_math_sin(doubleToBits(Double.infinity))).isNaN)
    }

    func testCosDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_cos(doubleToBits(Double.nan))).isNaN)
    }

    func testCosDoubleInfinity() {
        XCTAssertTrue(doubleFromBits(kk_math_cos(doubleToBits(Double.infinity))).isNaN)
    }

    func testTanDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_tan(doubleToBits(Double.nan))).isNaN)
    }

    func testTanDoubleInfinity() {
        // tan(±Inf) は未定義 → NaN (sin/cos と同じパターン)
        XCTAssertTrue(doubleFromBits(kk_math_tan(doubleToBits(Double.infinity))).isNaN)
        XCTAssertTrue(doubleFromBits(kk_math_tan(doubleToBits(-Double.infinity))).isNaN)
    }

    func testAsinDoubleOutOfRange() {
        // asin(x) for |x| > 1 is NaN
        XCTAssertTrue(doubleFromBits(kk_math_asin(doubleToBits(2.0))).isNaN)
        XCTAssertTrue(doubleFromBits(kk_math_asin(doubleToBits(-2.0))).isNaN)
    }

    func testAcosDoubleOutOfRange() {
        // acos(x) for |x| > 1 is NaN
        XCTAssertTrue(doubleFromBits(kk_math_acos(doubleToBits(2.0))).isNaN)
    }

    func testAtanDoubleInfinity() {
        // atan(+Inf) == pi/2
        let result = doubleFromBits(kk_math_atan(doubleToBits(Double.infinity)))
        XCTAssertEqual(result, Double.pi / 2, accuracy: 1e-12)
    }

    func testAtanDoubleNegativeInfinity() {
        // atan(-Inf) == -pi/2
        let result = doubleFromBits(kk_math_atan(doubleToBits(-Double.infinity)))
        XCTAssertEqual(result, -Double.pi / 2, accuracy: 1e-12)
    }

    func testAtan2DoubleSpecialCases() {
        // atan2(0, 0) == 0
        XCTAssertEqual(doubleFromBits(kk_math_atan2(doubleToBits(0.0), doubleToBits(0.0))), 0.0)
        // atan2(+Inf, +Inf) == pi/4
        let result = doubleFromBits(kk_math_atan2(doubleToBits(Double.infinity), doubleToBits(Double.infinity)))
        XCTAssertEqual(result, Double.pi / 4, accuracy: 1e-12)
    }

    func testAtan2DoubleSignedZeroY() {
        // atan2(-0.0, +x) == -0.0 (符号付きゼロの通過)
        let result = doubleFromBits(kk_math_atan2(doubleToBits(-0.0), doubleToBits(1.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertTrue(result.sign == .minus)
    }

    func testAtan2DoubleNegativeXAxis() {
        // atan2(+0, -x) == +π  /  atan2(-0, -x) == -π
        XCTAssertEqual(
            doubleFromBits(kk_math_atan2(doubleToBits(0.0),  doubleToBits(-1.0))),
             Double.pi, accuracy: 1e-12)
        XCTAssertEqual(
            doubleFromBits(kk_math_atan2(doubleToBits(-0.0), doubleToBits(-1.0))),
            -Double.pi, accuracy: 1e-12)
    }

    func testAtan2DoubleYInfinityXFinite() {
        // atan2(+Inf, finite) == +π/2  /  atan2(-Inf, finite) == -π/2
        XCTAssertEqual(
            doubleFromBits(kk_math_atan2(doubleToBits( Double.infinity), doubleToBits(1.0))),
             Double.pi / 2, accuracy: 1e-12)
        XCTAssertEqual(
            doubleFromBits(kk_math_atan2(doubleToBits(-Double.infinity), doubleToBits(1.0))),
            -Double.pi / 2, accuracy: 1e-12)
    }

    func testAtan2DoubleXInfinity() {
        // atan2(±y, +Inf) == ±0
        let posZero = doubleFromBits(kk_math_atan2(doubleToBits(1.0),  doubleToBits(Double.infinity)))
        XCTAssertEqual(posZero, 0.0, accuracy: 1e-12)
        let negZero = doubleFromBits(kk_math_atan2(doubleToBits(-1.0), doubleToBits(Double.infinity)))
        XCTAssertEqual(negZero, 0.0, accuracy: 1e-12)
        XCTAssertTrue(negZero.sign == .minus)
        // atan2(±y, -Inf) == ±π
        XCTAssertEqual(
            doubleFromBits(kk_math_atan2(doubleToBits(1.0),  doubleToBits(-Double.infinity))),
             Double.pi, accuracy: 1e-12)
        XCTAssertEqual(
            doubleFromBits(kk_math_atan2(doubleToBits(-1.0), doubleToBits(-Double.infinity))),
            -Double.pi, accuracy: 1e-12)
    }

    func testAtan2DoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_atan2(doubleToBits(Double.nan), doubleToBits(1.0))).isNaN)
        XCTAssertTrue(doubleFromBits(kk_math_atan2(doubleToBits(1.0), doubleToBits(Double.nan))).isNaN)
    }

    // MARK: - atan2 IEEE 754 完全テーブル補完 (TEST-MATH-024)

    func testAtan2DoubleSignedZeroPositiveZeroX() {
        // IEEE 754: atan2(+0, +0) == +0 (符号は正)
        let pos = doubleFromBits(kk_math_atan2(doubleToBits(0.0), doubleToBits(0.0)))
        XCTAssertEqual(pos, 0.0)
        XCTAssertFalse(pos.sign == .minus)
        // IEEE 754: atan2(-0, +0) == -0 (符号は負)
        let neg = doubleFromBits(kk_math_atan2(doubleToBits(-0.0), doubleToBits(0.0)))
        XCTAssertEqual(neg, 0.0)
        XCTAssertTrue(neg.sign == .minus)
    }

    func testAtan2DoubleSignedZeroNegativeZeroX() {
        // IEEE 754: atan2(+0, -0) == +π
        XCTAssertEqual(
            doubleFromBits(kk_math_atan2(doubleToBits(0.0), doubleToBits(-0.0))),
            Double.pi, accuracy: 1e-12)
        // IEEE 754: atan2(-0, -0) == -π
        XCTAssertEqual(
            doubleFromBits(kk_math_atan2(doubleToBits(-0.0), doubleToBits(-0.0))),
            -Double.pi, accuracy: 1e-12)
    }

    func testAtan2DoubleZeroYAtInfinityX() {
        // IEEE 754: atan2(+0, +Inf) == +0 (符号は正)
        let posAtPosInf = doubleFromBits(kk_math_atan2(doubleToBits(0.0), doubleToBits(Double.infinity)))
        XCTAssertEqual(posAtPosInf, 0.0)
        XCTAssertFalse(posAtPosInf.sign == .minus)
        // IEEE 754: atan2(-0, +Inf) == -0 (符号は負)
        let negAtPosInf = doubleFromBits(kk_math_atan2(doubleToBits(-0.0), doubleToBits(Double.infinity)))
        XCTAssertEqual(negAtPosInf, 0.0)
        XCTAssertTrue(negAtPosInf.sign == .minus)
        // IEEE 754: atan2(+0, -Inf) == +π
        XCTAssertEqual(
            doubleFromBits(kk_math_atan2(doubleToBits(0.0), doubleToBits(-Double.infinity))),
            Double.pi, accuracy: 1e-12)
        // IEEE 754: atan2(-0, -Inf) == -π
        XCTAssertEqual(
            doubleFromBits(kk_math_atan2(doubleToBits(-0.0), doubleToBits(-Double.infinity))),
            -Double.pi, accuracy: 1e-12)
    }

    func testAtan2DoubleInfinityBothArgs() {
        // IEEE 754: atan2(-Inf, +Inf) == -π/4
        XCTAssertEqual(
            doubleFromBits(kk_math_atan2(doubleToBits(-Double.infinity), doubleToBits(Double.infinity))),
            -Double.pi / 4, accuracy: 1e-12)
        // IEEE 754: atan2(+Inf, -Inf) == +3π/4
        XCTAssertEqual(
            doubleFromBits(kk_math_atan2(doubleToBits(Double.infinity), doubleToBits(-Double.infinity))),
            3 * Double.pi / 4, accuracy: 1e-12)
        // IEEE 754: atan2(-Inf, -Inf) == -3π/4
        XCTAssertEqual(
            doubleFromBits(kk_math_atan2(doubleToBits(-Double.infinity), doubleToBits(-Double.infinity))),
            -3 * Double.pi / 4, accuracy: 1e-12)
    }

    // MARK: - Float trig NaN / Inf propagation

    func testSinFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_sin_float(floatToBits(Float.nan))).isNaN)
    }

    func testSinFloatInfinity() {
        XCTAssertTrue(floatFromBits(kk_math_sin_float(floatToBits(Float.infinity))).isNaN)
    }

    func testCosFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_cos_float(floatToBits(Float.nan))).isNaN)
    }

    func testAsinFloatOutOfRange() {
        XCTAssertTrue(floatFromBits(kk_math_asin_float(floatToBits(2.0))).isNaN)
    }

    func testAcosFloatOutOfRange() {
        XCTAssertTrue(floatFromBits(kk_math_acos_float(floatToBits(2.0))).isNaN)
    }

    func testTanFloatInfinity() {
        XCTAssertTrue(floatFromBits(kk_math_tan_float(floatToBits(Float.infinity))).isNaN)
        XCTAssertTrue(floatFromBits(kk_math_tan_float(floatToBits(-Float.infinity))).isNaN)
    }

    // MARK: - atan2(Float) IEEE 754 edge cases (TEST-MATH-024)

    func testAtan2FloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_atan2_float(floatToBits(Float.nan), floatToBits(1.0))).isNaN)
        XCTAssertTrue(floatFromBits(kk_math_atan2_float(floatToBits(1.0), floatToBits(Float.nan))).isNaN)
    }

    func testAtan2FloatInfinityXFinite() {
        // atan2(+Inf, finite) == +π/2
        let posHalfPi = floatFromBits(kk_math_atan2_float(floatToBits(Float.infinity), floatToBits(1.0)))
        XCTAssertEqual(posHalfPi, Float.pi / 2, accuracy: 1e-6)
        // atan2(-Inf, finite) == -π/2 (奇関数の対称性)
        let negHalfPi = floatFromBits(kk_math_atan2_float(floatToBits(-Float.infinity), floatToBits(1.0)))
        XCTAssertEqual(negHalfPi, -Float.pi / 2, accuracy: 1e-6)
    }

    func testAtan2FloatSignedZero() {
        // IEEE 754: atan2(-0, +0) == -0 (符号保持)
        let result = floatFromBits(kk_math_atan2_float(floatToBits(-0.0), floatToBits(0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertTrue(result.sign == .minus)
    }

    func testAtan2FloatInfinityBothArgs() {
        // IEEE 754: atan2(-Inf, +Inf) == -π/4
        XCTAssertEqual(
            floatFromBits(kk_math_atan2_float(floatToBits(-Float.infinity), floatToBits(Float.infinity))),
            -Float.pi / 4, accuracy: 1e-6)
        // IEEE 754: atan2(+Inf, -Inf) == +3π/4
        XCTAssertEqual(
            floatFromBits(kk_math_atan2_float(floatToBits(Float.infinity), floatToBits(-Float.infinity))),
            3 * Float.pi / 4, accuracy: 1e-6)
        // IEEE 754: atan2(-Inf, -Inf) == -3π/4
        XCTAssertEqual(
            floatFromBits(kk_math_atan2_float(floatToBits(-Float.infinity), floatToBits(-Float.infinity))),
            -3 * Float.pi / 4, accuracy: 1e-6)
    }

    // MARK: - Hyperbolic functions (Double)

    func testSinhDoubleZero() {
        XCTAssertEqual(doubleFromBits(kk_math_sinh(doubleToBits(0.0))), 0.0, accuracy: 1e-12)
    }

    func testSinhDoubleInfinity() {
        XCTAssertTrue(doubleFromBits(kk_math_sinh(doubleToBits(Double.infinity))).isInfinite)
    }

    func testSinhDoubleNegativeInfinity() {
        // sinh は奇関数: sinh(-Inf) == -Inf
        let result = doubleFromBits(kk_math_sinh(doubleToBits(-Double.infinity)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertLessThan(result, 0)
    }

    func testSinhDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_sinh(doubleToBits(Double.nan))).isNaN)
    }

    func testCoshDoubleZero() {
        XCTAssertEqual(doubleFromBits(kk_math_cosh(doubleToBits(0.0))), 1.0, accuracy: 1e-12)
    }

    func testCoshDoubleInfinity() {
        XCTAssertTrue(doubleFromBits(kk_math_cosh(doubleToBits(Double.infinity))).isInfinite)
    }

    func testCoshDoubleNegativeInfinity() {
        // cosh は偶関数: cosh(-Inf) == +Inf
        let result = doubleFromBits(kk_math_cosh(doubleToBits(-Double.infinity)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    func testCoshDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_cosh(doubleToBits(Double.nan))).isNaN)
    }

    func testTanhDoubleZero() {
        XCTAssertEqual(doubleFromBits(kk_math_tanh(doubleToBits(0.0))), 0.0, accuracy: 1e-12)
    }

    func testTanhDoubleInfinity() {
        // tanh(+Inf) == 1.0
        XCTAssertEqual(doubleFromBits(kk_math_tanh(doubleToBits(Double.infinity))), 1.0, accuracy: 1e-12)
    }

    func testTanhDoubleNegativeInfinity() {
        // tanh は奇関数: tanh(-Inf) == -1.0
        XCTAssertEqual(doubleFromBits(kk_math_tanh(doubleToBits(-Double.infinity))), -1.0, accuracy: 1e-12)
    }

    func testTanhDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_tanh(doubleToBits(Double.nan))).isNaN)
    }

    // MARK: - Hyperbolic functions (Float)

    func testSinhFloatZero() {
        XCTAssertEqual(floatFromBits(kk_math_sinh_float(floatToBits(0.0))), 0.0, accuracy: 1e-6)
    }

    func testSinhFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_sinh_float(floatToBits(Float.nan))).isNaN)
    }

    func testSinhFloatNegativeInfinity() {
        let result = floatFromBits(kk_math_sinh_float(floatToBits(-Float.infinity)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertLessThan(result, 0)
    }

    func testCoshFloatZero() {
        XCTAssertEqual(floatFromBits(kk_math_cosh_float(floatToBits(0.0))), 1.0, accuracy: 1e-6)
    }

    func testCoshFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_cosh_float(floatToBits(Float.nan))).isNaN)
    }

    func testCoshFloatNegativeInfinity() {
        // cosh は偶関数: cosh(-Inf) == +Inf
        let result = floatFromBits(kk_math_cosh_float(floatToBits(-Float.infinity)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    func testTanhFloatInfinity() {
        XCTAssertEqual(floatFromBits(kk_math_tanh_float(floatToBits(Float.infinity))), 1.0, accuracy: 1e-6)
    }

    func testTanhFloatNegativeInfinity() {
        XCTAssertEqual(floatFromBits(kk_math_tanh_float(floatToBits(-Float.infinity))), -1.0, accuracy: 1e-6)
    }

    func testTanhFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_tanh_float(floatToBits(Float.nan))).isNaN)
    }

    // MARK: - Inverse hyperbolic functions (Double)

    func testAcoshDoubleOne() {
        // acosh(1) == 0
        XCTAssertEqual(doubleFromBits(kk_math_acosh(doubleToBits(1.0))), 0.0, accuracy: 1e-12)
    }

    func testAcoshDoubleOutOfRange() {
        // acosh(x) for x < 1 is NaN
        XCTAssertTrue(doubleFromBits(kk_math_acosh(doubleToBits(0.5))).isNaN)
    }

    func testAcoshDoubleInfinity() {
        XCTAssertTrue(doubleFromBits(kk_math_acosh(doubleToBits(Double.infinity))).isInfinite)
    }

    func testAsinhDoubleZero() {
        XCTAssertEqual(doubleFromBits(kk_math_asinh(doubleToBits(0.0))), 0.0, accuracy: 1e-12)
    }

    func testAsinhDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_asinh(doubleToBits(Double.nan))).isNaN)
    }

    func testAtanhDoubleZero() {
        XCTAssertEqual(doubleFromBits(kk_math_atanh(doubleToBits(0.0))), 0.0, accuracy: 1e-12)
    }

    func testAtanhDoubleOutOfRange() {
        // atanh(x) for |x| > 1 is NaN
        XCTAssertTrue(doubleFromBits(kk_math_atanh(doubleToBits(2.0))).isNaN)
    }

    func testAtanhDoubleOne() {
        // atanh(1) == +Inf
        XCTAssertTrue(doubleFromBits(kk_math_atanh(doubleToBits(1.0))).isInfinite)
    }

    func testAtanhDoubleNegativeOne() {
        // atanh は奇関数: atanh(-1) == -Inf
        let result = doubleFromBits(kk_math_atanh(doubleToBits(-1.0)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertLessThan(result, 0)
    }

    // MARK: - Inverse hyperbolic functions (Float)

    func testAcoshFloatOne() {
        XCTAssertEqual(floatFromBits(kk_math_acosh_float(floatToBits(1.0))), 0.0, accuracy: 1e-6)
    }

    func testAcoshFloatOutOfRange() {
        XCTAssertTrue(floatFromBits(kk_math_acosh_float(floatToBits(0.5))).isNaN)
    }

    func testAsinhFloatZero() {
        XCTAssertEqual(floatFromBits(kk_math_asinh_float(floatToBits(0.0))), 0.0, accuracy: 1e-6)
    }

    func testAtanhFloatOne() {
        XCTAssertTrue(floatFromBits(kk_math_atanh_float(floatToBits(1.0))).isInfinite)
    }

    func testAtanhFloatNegativeOne() {
        let result = floatFromBits(kk_math_atanh_float(floatToBits(-1.0)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertLessThan(result, 0)
    }

    // MARK: - cbrt(Double) edge cases

    func testCbrtDoubleNegative() {
        // cbrt(-8) == -2
        XCTAssertEqual(doubleFromBits(kk_math_cbrt(doubleToBits(-8.0))), -2.0, accuracy: 1e-12)
    }

    func testCbrtDoubleZero() {
        XCTAssertEqual(doubleFromBits(kk_math_cbrt(doubleToBits(0.0))), 0.0)
    }

    func testCbrtDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_cbrt(doubleToBits(Double.nan))).isNaN)
    }

    func testCbrtDoubleInfinity() {
        XCTAssertTrue(doubleFromBits(kk_math_cbrt(doubleToBits(Double.infinity))).isInfinite)
    }

    func testCbrtDoubleNegativeZero() {
        // cbrt は奇関数: cbrt(-0.0) == -0.0
        let result = doubleFromBits(kk_math_cbrt(doubleToBits(-0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertTrue(result.sign == .minus)
    }

    func testCbrtDoubleNegativeInfinity() {
        // cbrt(-Inf) == -Inf
        let result = doubleFromBits(kk_math_cbrt(doubleToBits(-Double.infinity)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertLessThan(result, 0)
    }

    // MARK: - cbrt(Float) edge cases

    func testCbrtFloatNegative() {
        XCTAssertEqual(floatFromBits(kk_math_cbrt_float(floatToBits(-8.0))), -2.0, accuracy: 1e-6)
    }

    func testCbrtFloatZero() {
        XCTAssertEqual(floatFromBits(kk_math_cbrt_float(floatToBits(0.0))), 0.0)
    }

    func testCbrtFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_cbrt_float(floatToBits(Float.nan))).isNaN)
    }

    func testCbrtFloatNegativeZero() {
        let result = floatFromBits(kk_math_cbrt_float(floatToBits(-0.0)))
        XCTAssertEqual(result, 0.0)
        XCTAssertTrue(result.sign == .minus)
    }

    func testCbrtFloatInfinity() {
        // +Inf → +Inf, -Inf → -Inf
        XCTAssertTrue(floatFromBits(kk_math_cbrt_float(floatToBits(Float.infinity))).isInfinite)
        let neg = floatFromBits(kk_math_cbrt_float(floatToBits(-Float.infinity)))
        XCTAssertTrue(neg.isInfinite)
        XCTAssertLessThan(neg, 0)
    }

    // MARK: - IEEErem (Double) edge cases

    func testIEEEremDoubleBasic() {
        // IEEE remainder: 5.0 rem 3.0 == -1.0 (nearest-integer remainder)
        XCTAssertEqual(doubleFromBits(kk_math_IEEErem(doubleToBits(5.0), doubleToBits(3.0))), -1.0, accuracy: 1e-12)
    }

    func testIEEEremDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_IEEErem(doubleToBits(Double.nan), doubleToBits(1.0))).isNaN)
    }

    func testIEEEremDoubleZeroDivisor() {
        XCTAssertTrue(doubleFromBits(kk_math_IEEErem(doubleToBits(5.0), doubleToBits(0.0))).isNaN)
    }

    // MARK: - IEEErem (Float) edge cases

    func testIEEEremFloatBasic() {
        XCTAssertEqual(floatFromBits(kk_math_IEEErem_float(floatToBits(5.0), floatToBits(3.0))), -1.0, accuracy: 1e-6)
    }

    func testIEEEremFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_math_IEEErem_float(floatToBits(Float.nan), floatToBits(1.0))).isNaN)
    }

    // MARK: - withSign (copysign) edge cases

    func testWithSignDoublePositiveSign() {
        // copysign(-3.0, +1.0) == +3.0
        XCTAssertEqual(doubleFromBits(kk_math_withSign(doubleToBits(-3.0), doubleToBits(1.0))), 3.0)
    }

    func testWithSignDoubleNegativeSign() {
        XCTAssertEqual(doubleFromBits(kk_math_withSign(doubleToBits(3.0), doubleToBits(-1.0))), -3.0)
    }

    func testWithSignDoubleNegativeZeroSign() {
        // Sign of -0.0 is negative
        let result = doubleFromBits(kk_math_withSign(doubleToBits(3.0), doubleToBits(-0.0)))
        XCTAssertEqual(result, -3.0)
    }

    func testWithSignFloatPositiveSign() {
        XCTAssertEqual(floatFromBits(kk_math_withSign_float(floatToBits(-3.0), floatToBits(1.0))), 3.0)
    }

    func testWithSignFloatNegativeSign() {
        XCTAssertEqual(floatFromBits(kk_math_withSign_float(floatToBits(3.0), floatToBits(-1.0))), -3.0)
    }

    func testWithSignFloatIntSign() {
        XCTAssertEqual(floatFromBits(kk_math_withSign_float_int(floatToBits(-3.0), 1)), 3.0)
        XCTAssertEqual(floatFromBits(kk_math_withSign_float_int(floatToBits(3.0), -1)), -3.0)
    }

    // MARK: - nextTowards edge cases

    func testNextTowardsDoubleUp() {
        // nextafter(1.0, +Inf) == 1.0.nextUp
        let result = doubleFromBits(kk_math_nextTowards(doubleToBits(1.0), doubleToBits(Double.infinity)))
        XCTAssertEqual(result, Double(1.0).nextUp)
    }

    func testNextTowardsDoubleDown() {
        // nextafter(1.0, -Inf) == 1.0.nextDown
        let result = doubleFromBits(kk_math_nextTowards(doubleToBits(1.0), doubleToBits(-Double.infinity)))
        XCTAssertEqual(result, Double(1.0).nextDown)
    }

    func testNextTowardsDoubleSame() {
        // nextafter(x, x) == x
        let result = doubleFromBits(kk_math_nextTowards(doubleToBits(1.0), doubleToBits(1.0)))
        XCTAssertEqual(result, 1.0)
    }

    func testNextTowardsDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_math_nextTowards(doubleToBits(Double.nan), doubleToBits(1.0))).isNaN)
    }

    func testNextTowardsFloat() {
        XCTAssertEqual(
            floatFromBits(kk_math_nextTowards_float(floatToBits(1.0), floatToBits(Float.infinity))),
            Float(1.0).nextUp
        )
        XCTAssertEqual(
            floatFromBits(kk_math_nextTowards_float(floatToBits(1.0), floatToBits(-Float.infinity))),
            Float(1.0).nextDown
        )
        XCTAssertTrue(floatFromBits(kk_math_nextTowards_float(floatToBits(Float.nan), floatToBits(1.0))).isNaN)
    }

    // MARK: - ulp edge cases (Double)

    func testUlpDoubleZero() {
        // ulp(0.0) == leastNonzeroMagnitude (subnormal)
        let result = doubleFromBits(kk_double_ulp(doubleToBits(0.0)))
        XCTAssertEqual(result, Double(0.0).ulp)
    }

    func testUlpDoubleInfinity() {
        // ulp(Inf) == NaN (IEEE 754)
        let result = doubleFromBits(kk_double_ulp(doubleToBits(Double.infinity)))
        XCTAssertTrue(result.isNaN)
    }

    func testUlpDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_double_ulp(doubleToBits(Double.nan))).isNaN)
    }

    func testUlpDoubleNegativeInfinity() {
        // ulp(-Inf) == NaN (正の無限大と対称)
        XCTAssertTrue(doubleFromBits(kk_double_ulp(doubleToBits(-Double.infinity))).isNaN)
    }

    func testUlpDoubleNegativeZero() {
        // ulp(-0.0) == ulp(+0.0) = leastNonzeroMagnitude (大きさのみ依存)
        let result = doubleFromBits(kk_double_ulp(doubleToBits(-0.0)))
        XCTAssertEqual(result, Double(0.0).ulp)
    }

    // MARK: - ulp edge cases (Float)

    func testUlpFloatZero() {
        let result = floatFromBits(kk_float_ulp(floatToBits(0.0)))
        XCTAssertEqual(result, Float(0.0).ulp)
    }

    func testUlpFloatInfinity() {
        // ulp(Inf) == NaN (IEEE 754)
        let result = floatFromBits(kk_float_ulp(floatToBits(Float.infinity)))
        XCTAssertTrue(result.isNaN)
    }

    func testUlpFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_float_ulp(floatToBits(Float.nan))).isNaN)
    }

    func testUlpFloatNegativeInfinity() {
        XCTAssertTrue(floatFromBits(kk_float_ulp(floatToBits(-Float.infinity))).isNaN)
    }

    // MARK: - nextUp / nextDown at boundaries (Double)

    func testNextUpDoubleMaxFinite() {
        // nextUp(Double.greatestFiniteMagnitude) == +Inf
        let result = doubleFromBits(kk_double_nextUp(doubleToBits(Double.greatestFiniteMagnitude)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertGreaterThan(result, 0)
    }

    func testNextDownDoubleNegativeMaxFinite() {
        // nextDown(-Double.greatestFiniteMagnitude) == -Inf
        let result = doubleFromBits(kk_double_nextDown(doubleToBits(-Double.greatestFiniteMagnitude)))
        XCTAssertTrue(result.isInfinite)
        XCTAssertLessThan(result, 0)
    }

    func testNextUpDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_double_nextUp(doubleToBits(Double.nan))).isNaN)
    }

    func testNextDownDoubleNaN() {
        XCTAssertTrue(doubleFromBits(kk_double_nextDown(doubleToBits(Double.nan))).isNaN)
    }

    func testNextUpDoubleNegativeInfinity() {
        // nextUp(-Inf) == -Double.greatestFiniteMagnitude
        let result = doubleFromBits(kk_double_nextUp(doubleToBits(-Double.infinity)))
        XCTAssertEqual(result, -Double.greatestFiniteMagnitude)
    }

    func testNextDownDoublePositiveInfinity() {
        // nextDown(+Inf) == Double.greatestFiniteMagnitude
        let result = doubleFromBits(kk_double_nextDown(doubleToBits(Double.infinity)))
        XCTAssertEqual(result, Double.greatestFiniteMagnitude)
    }

    // MARK: - nextUp / nextDown at boundaries (Float)

    func testNextUpFloatMaxFinite() {
        let result = floatFromBits(kk_float_nextUp(floatToBits(Float.greatestFiniteMagnitude)))
        XCTAssertTrue(result.isInfinite)
    }

    func testNextDownFloatNaN() {
        XCTAssertTrue(floatFromBits(kk_float_nextDown(floatToBits(Float.nan))).isNaN)
    }

    func testNextUpFloatNegativeInfinity() {
        // nextUp(-Inf) == -Float.greatestFiniteMagnitude
        let result = floatFromBits(kk_float_nextUp(floatToBits(-Float.infinity)))
        XCTAssertEqual(result, -Float.greatestFiniteMagnitude)
    }

    func testNextDownFloatPositiveInfinity() {
        // nextDown(+Inf) == Float.greatestFiniteMagnitude
        let result = floatFromBits(kk_float_nextDown(floatToBits(Float.infinity)))
        XCTAssertEqual(result, Float.greatestFiniteMagnitude)
    }

    // MARK: - Conversion edge cases

    func testIntToLongNegative() {
        XCTAssertEqual(kk_int_to_long(Int(Int32.min)), Int(Int32.min))
    }

    func testLongToIntOverflow() {
        // Long value larger than Int32.max saturates? Actually kk_long_to_int wraps (truncates).
        let result = kk_long_to_int(Int(Int32.max) + 1)
        XCTAssertEqual(result, Int(Int32.min))
    }

    func testLongToByteEdge() {
        XCTAssertEqual(kk_long_to_byte(127), 127)
        XCTAssertEqual(kk_long_to_byte(128), -128)
        XCTAssertEqual(kk_long_to_byte(-129), 127)
    }

    func testLongToShortEdge() {
        XCTAssertEqual(kk_long_to_short(32767), 32767)
        XCTAssertEqual(kk_long_to_short(32768), -32768)
    }

    func testLongToFloatLargeValue() {
        // Very large long converted to float (precision loss expected, but no NaN/Inf)
        let result = floatFromBits(kk_long_to_float(Int(Int64.max)))
        XCTAssertFalse(result.isNaN)
        XCTAssertGreaterThan(result, 0)
    }

    func testLongToDoubleLargeValue() {
        let result = doubleFromBits(kk_long_to_double(Int(Int64.max)))
        XCTAssertFalse(result.isNaN)
        XCTAssertGreaterThan(result, 0)
    }

    // MARK: - Double/Float to Int/Long conversion at boundary

    func testDoubleToIntExactBoundary() {
        // Exactly Int32.max as double
        XCTAssertEqual(kk_double_to_int(doubleToBits(Double(Int32.max))), Int(Int32.max))
    }

    func testDoubleToIntNaN() {
        XCTAssertEqual(kk_double_to_int(doubleToBits(Double.nan)), 0)
    }

    func testDoubleToIntPositiveInfinity() {
        XCTAssertEqual(kk_double_to_int(doubleToBits(Double.infinity)), Int(Int32.max))
    }

    func testDoubleToIntNegativeInfinity() {
        XCTAssertEqual(kk_double_to_int(doubleToBits(-Double.infinity)), Int(Int32.min))
    }

    func testFloatToIntNaN() {
        XCTAssertEqual(kk_float_to_int(floatToBits(Float.nan)), 0)
    }

    func testFloatToIntPositiveInfinity() {
        XCTAssertEqual(kk_float_to_int(floatToBits(Float.infinity)), Int(Int32.max))
    }

    func testFloatToIntNegativeInfinity() {
        XCTAssertEqual(kk_float_to_int(floatToBits(-Float.infinity)), Int(Int32.min))
    }

    func testDoubleToLongNaN() {
        XCTAssertEqual(kk_double_to_long(doubleToBits(Double.nan)), 0)
    }

    func testDoubleToLongPositiveInfinity() {
        XCTAssertEqual(kk_double_to_long(doubleToBits(Double.infinity)), Int(Int64.max))
    }

    func testDoubleToLongNegativeInfinity() {
        XCTAssertEqual(kk_double_to_long(doubleToBits(-Double.infinity)), Int(Int64.min))
    }
}
