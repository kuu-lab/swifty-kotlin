#if canImport(Testing)
import Testing
@testable import Runtime

/// STDLIB-MATH-003: kotlin.math runtime / ABI boundary value and edge case coverage.
///
/// This file tests IEEE 754 special inputs (NaN, ±Infinity, ±0.0, subnormals)
/// and saturation / overflow behaviour for every kotlin.math entry point that
/// is not already exhaustively exercised in RuntimeMathTests.swift.
@Suite
struct RuntimeMathEdgeCaseTests {

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

    @Test
    func testAbsDoublePositiveZero() {
        // abs(+0.0) == +0.0
        let result = doubleFromBits(kk_math_abs(doubleToBits(0.0)))
        #expect(result == 0.0)
        #expect(!(result.sign == .minus))
    }

    @Test
    func testAbsDoubleNegativeZero() {
        // abs(-0.0) == +0.0 (sign bit cleared)
        let result = doubleFromBits(kk_math_abs(doubleToBits(-0.0)))
        #expect(result == 0.0)
        #expect(!(result.sign == .minus))
    }

    @Test
    func testAbsDoublePositiveInfinity() {
        let result = doubleFromBits(kk_math_abs(doubleToBits(Double.infinity)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    @Test
    func testAbsDoubleNegativeInfinity() {
        // abs(-Inf) == +Inf
        let result = doubleFromBits(kk_math_abs(doubleToBits(-Double.infinity)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    @Test
    func testAbsDoubleSubnormal() {
        // abs of smallest subnormal should stay subnormal with same magnitude
        let sub = Double.leastNonzeroMagnitude
        #expect(doubleFromBits(kk_math_abs(doubleToBits(-sub))) == sub)
    }

    // MARK: - abs(Float) IEEE 754 edge cases

    @Test
    func testAbsFloatNegativeZero() {
        let result = floatFromBits(kk_math_abs_float(floatToBits(-0.0)))
        #expect(result == 0.0)
        #expect(!(result.sign == .minus))
    }

    @Test
    func testAbsFloatInfinity() {
        #expect(floatFromBits(kk_math_abs_float(floatToBits(Float.infinity))).isInfinite)
        #expect(floatFromBits(kk_math_abs_float(floatToBits(-Float.infinity))).isInfinite)
        #expect(floatFromBits(kk_math_abs_float(floatToBits(-Float.infinity))) > 0)
    }

    @Test
    func testAbsFloatSubnormal() {
        let sub = Float.leastNonzeroMagnitude
        #expect(floatFromBits(kk_math_abs_float(floatToBits(-sub))) == sub)
    }

    // MARK: - abs(Long) overflow

    @Test
    func testAbsLongMinValue() {
        // abs(Long.MIN_VALUE) overflows and stays Long.MIN_VALUE (Kotlin spec)
        #expect(kk_math_abs_long(Int(truncatingIfNeeded: Int64.min)) == Int(truncatingIfNeeded: Int64.min))
    }

    @Test
    func testAbsLongPositive() {
        #expect(kk_math_abs_long(42) == 42)
    }

    @Test
    func testAbsLongNegative() {
        #expect(kk_math_abs_long(-42) == 42)
    }

    // MARK: - sqrt(Double) IEEE 754 edge cases

    @Test
    func testSqrtDoubleZero() {
        #expect(doubleFromBits(kk_math_sqrt(doubleToBits(0.0))) == 0.0)
    }

    @Test
    func testSqrtDoubleNegativeZero() {
        // sqrt(-0.0) == -0.0 (IEEE 754)
        let result = doubleFromBits(kk_math_sqrt(doubleToBits(-0.0)))
        #expect(result == 0.0)
        #expect(result.sign == .minus)
    }

    @Test
    func testSqrtDoubleInfinity() {
        // sqrt(+Inf) == +Inf
        let result = doubleFromBits(kk_math_sqrt(doubleToBits(Double.infinity)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    @Test
    func testSqrtDoubleNaN() {
        #expect(doubleFromBits(kk_math_sqrt(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testSqrtDoubleNegative() {
        // sqrt of a negative number is NaN
        #expect(doubleFromBits(kk_math_sqrt(doubleToBits(-1.0))).isNaN)
    }

    // MARK: - sqrt(Float) IEEE 754 edge cases

    @Test
    func testSqrtFloatZero() {
        #expect(floatFromBits(kk_math_sqrt_float(floatToBits(0.0))) == 0.0)
    }

    @Test
    func testSqrtFloatNaN() {
        #expect(floatFromBits(kk_math_sqrt_float(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testSqrtFloatNegative() {
        #expect(floatFromBits(kk_math_sqrt_float(floatToBits(-1.0))).isNaN)
    }

    @Test
    func testSqrtFloatInfinity() {
        let result = floatFromBits(kk_math_sqrt_float(floatToBits(Float.infinity)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    // MARK: - pow(Double) special cases

    @Test
    func testPowDoubleNaNBase() {
        #expect(doubleFromBits(kk_math_pow(doubleToBits(Double.nan), doubleToBits(2.0))).isNaN)
    }

    @Test
    func testPowDoubleNaNExp() {
        #expect(doubleFromBits(kk_math_pow(doubleToBits(2.0), doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testPowDoubleZeroExponent() {
        // x^0 == 1 for any x (including NaN, Inf)
        #expect(doubleFromBits(kk_math_pow(doubleToBits(Double.nan), doubleToBits(0.0))) == 1.0)
        #expect(doubleFromBits(kk_math_pow(doubleToBits(Double.infinity), doubleToBits(0.0))) == 1.0)
        #expect(doubleFromBits(kk_math_pow(doubleToBits(0.0), doubleToBits(0.0))) == 1.0)
    }

    @Test
    func testPowDoubleInfinityBase() {
        // Inf^2 == Inf; Inf^(-1) == 0
        let infSquared = doubleFromBits(kk_math_pow(doubleToBits(Double.infinity), doubleToBits(2.0)))
        #expect(infSquared.isInfinite)
        let infToMinusOne = doubleFromBits(kk_math_pow(doubleToBits(Double.infinity), doubleToBits(-1.0)))
        #expect(infToMinusOne == 0.0)
    }

    @Test
    func testPowDoubleOneBase() {
        // 1^anything == 1 (including NaN exponent by IEEE 754)
        #expect(doubleFromBits(kk_math_pow(doubleToBits(1.0), doubleToBits(Double.nan))) == 1.0)
        #expect(doubleFromBits(kk_math_pow(doubleToBits(1.0), doubleToBits(Double.infinity))) == 1.0)
    }

    @Test
    func testPowDoubleNegativeBaseNonIntegerExp() {
        // pow(negative, non-integer) = NaN (C99 Annex F §F.9.4.4)
        #expect(doubleFromBits(kk_math_pow(doubleToBits(-2.0), doubleToBits(0.5))).isNaN)
        #expect(doubleFromBits(kk_math_pow(doubleToBits(-3.0), doubleToBits(1.5))).isNaN)
    }

    @Test
    func testPowDoubleZeroBaseNegativeExp() {
        // pow(+0.0, negative) = +Inf (IEEE 754)
        let result = doubleFromBits(kk_math_pow(doubleToBits(0.0), doubleToBits(-1.0)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    @Test
    func testPowDoubleNegativeZeroBaseNegativeOddIntExp() {
        // pow(-0.0, negative odd integer) = -Inf; negative even integer → +Inf
        let negOdd1 = doubleFromBits(kk_math_pow(doubleToBits(-0.0), doubleToBits(-1.0)))
        #expect(negOdd1.isInfinite)
        #expect(negOdd1 < 0)
        let negOdd3 = doubleFromBits(kk_math_pow(doubleToBits(-0.0), doubleToBits(-3.0)))
        #expect(negOdd3.isInfinite)
        #expect(negOdd3 < 0)
        let negEven = doubleFromBits(kk_math_pow(doubleToBits(-0.0), doubleToBits(-2.0)))
        #expect(negEven.isInfinite)
        #expect(negEven > 0)
    }

    @Test
    func testPowDoubleNegativeOneBaseInfinityExp() {
        // pow(-1.0, ±Inf) = 1.0 (IEEE 754)
        #expect(doubleFromBits(kk_math_pow(doubleToBits(-1.0), doubleToBits(Double.infinity))) == 1.0)
        #expect(doubleFromBits(kk_math_pow(doubleToBits(-1.0), doubleToBits(-Double.infinity))) == 1.0)
    }

    @Test
    func testPowDoubleInfinityBaseNegativeExpSign() {
        // pow(+Inf, negative) = +0.0; sign bit must be positive
        let result = doubleFromBits(kk_math_pow(doubleToBits(Double.infinity), doubleToBits(-1.0)))
        #expect(result == 0.0)
        #expect(!(result.sign == .minus))
    }

    // MARK: - pow(Float, Float) IEEE 754 special cases

    @Test
    func testPowFloatNegativeBaseNonIntegerExp() {
        // pow(negative, non-integer) = NaN
        #expect(floatFromBits(kk_math_pow_float(floatToBits(-2.0), floatToBits(0.5))).isNaN)
    }

    @Test
    func testPowFloatZeroBaseNegativeExp() {
        // pow(+0.0f, negative) = +Inf
        let result = floatFromBits(kk_math_pow_float(floatToBits(0.0), floatToBits(-1.0)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    @Test
    func testPowFloatNegativeZeroBaseNegativeOddIntExp() {
        // pow(-0.0f, negative odd integer) = -Inf
        let result = floatFromBits(kk_math_pow_float(floatToBits(-0.0), floatToBits(-1.0)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    @Test
    func testPowFloatNegativeOneBaseInfinityExp() {
        // pow(-1.0f, ±Inf) = 1.0
        #expect(floatFromBits(kk_math_pow_float(floatToBits(-1.0), floatToBits(Float.infinity))) == 1.0)
        #expect(floatFromBits(kk_math_pow_float(floatToBits(-1.0), floatToBits(-Float.infinity))) == 1.0)
    }

    @Test
    func testPowFloatInfinityBaseNegativeExpSign() {
        // pow(+Inf, negative) = +0.0f
        let result = floatFromBits(kk_math_pow_float(floatToBits(Float.infinity), floatToBits(-1.0)))
        #expect(result == 0.0)
        #expect(!(result.sign == .minus))
    }

    @Test
    func testPowFloatAndIntOverloads() {
        #expect(abs((floatFromBits(kk_math_pow_float(floatToBits(2.0), floatToBits(3.0)))) - (8.0)) <= 1e-6)
        #expect(abs((doubleFromBits(kk_math_pow_int(doubleToBits(2.0), 3))) - (8.0)) <= 1e-12)
        #expect(abs((floatFromBits(kk_math_pow_float_int(floatToBits(2.0), 3))) - (8.0)) <= 1e-6)
        #expect(floatFromBits(kk_math_pow_float(floatToBits(Float.nan), floatToBits(2.0))).isNaN)
    }

    // MARK: - pow_int (Double, Int) IEEE 754 special cases

    @Test
    func testPowIntExpZeroBaseNegativeExp() {
        // pow(+0.0, -n) = +Inf
        let result = doubleFromBits(kk_math_pow_int(doubleToBits(0.0), -1))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    @Test
    func testPowIntExpNegativeZeroBaseNegativeOddExp() {
        // pow(-0.0, -odd) = -Inf (Int exponent converted to Double(-1.0))
        let result = doubleFromBits(kk_math_pow_int(doubleToBits(-0.0), -1))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    @Test
    func testPowIntExpInfinityBaseNegativeExp() {
        // pow(+Inf, -n) = +0.0
        let result = doubleFromBits(kk_math_pow_int(doubleToBits(Double.infinity), -1))
        #expect(result == 0.0)
        #expect(!(result.sign == .minus))
    }

    // MARK: - pow_float_int (Float, Int) IEEE 754 special cases

    @Test
    func testPowFloatIntExpZeroBaseNegativeExp() {
        // pow(+0.0f, -n) = +Inf
        let result = floatFromBits(kk_math_pow_float_int(floatToBits(0.0), -1))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    @Test
    func testPowFloatIntExpNegativeZeroBaseNegativeOddExp() {
        // pow(-0.0f, -odd) = -Inf
        let result = floatFromBits(kk_math_pow_float_int(floatToBits(-0.0), -1))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    @Test
    func testPowFloatIntExpInfinityBaseNegativeExp() {
        // pow(+Inf, -n) = +0.0f
        let result = floatFromBits(kk_math_pow_float_int(floatToBits(Float.infinity), -1))
        #expect(result == 0.0)
        #expect(!(result.sign == .minus))
    }

    // MARK: - ceil / floor / truncate with special values

    @Test
    func testCeilDoubleNaN() {
        #expect(doubleFromBits(kk_math_ceil(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testCeilDoubleInfinity() {
        #expect(doubleFromBits(kk_math_ceil(doubleToBits(Double.infinity))).isInfinite)
        #expect(doubleFromBits(kk_math_ceil(doubleToBits(-Double.infinity))).isInfinite)
    }

    @Test
    func testCeilDoubleNegativeZero() {
        // ceil(-0.0) == -0.0
        let result = doubleFromBits(kk_math_ceil(doubleToBits(-0.0)))
        #expect(result == 0.0)
    }

    @Test
    func testFloorDoubleNaN() {
        #expect(doubleFromBits(kk_math_floor(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testFloorDoubleInfinity() {
        #expect(doubleFromBits(kk_math_floor(doubleToBits(Double.infinity))).isInfinite)
        #expect(doubleFromBits(kk_math_floor(doubleToBits(-Double.infinity))).isInfinite)
    }

    @Test
    func testFloorDoubleNegativeZero() {
        // floor(-0.0) == -0.0 (IEEE 754 符号保持)
        let result = doubleFromBits(kk_math_floor(doubleToBits(-0.0)))
        #expect(result == 0.0)
        #expect(result.sign == .minus)
    }

    @Test
    func testTruncateDoubleNaN() {
        #expect(doubleFromBits(kk_math_truncate(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testTruncateDoubleInfinity() {
        #expect(doubleFromBits(kk_math_truncate(doubleToBits(Double.infinity))).isInfinite)
        #expect(doubleFromBits(kk_math_truncate(doubleToBits(-Double.infinity))).isInfinite)
    }

    @Test
    func testTruncateDoubleRoundsTowardZero() {
        #expect(doubleFromBits(kk_math_truncate(doubleToBits(2.9))) == 2.0)
        #expect(doubleFromBits(kk_math_truncate(doubleToBits(-2.9))) == -2.0)
    }

    @Test
    func testTruncateFloatRoundsTowardZero() {
        #expect(floatFromBits(kk_math_truncate_float(floatToBits(2.9))) == 2.0)
        #expect(floatFromBits(kk_math_truncate_float(floatToBits(-2.9))) == -2.0)
    }

    @Test
    func testTruncateFloatNaN() {
        #expect(floatFromBits(kk_math_truncate_float(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testTruncateDoubleNegativeZero() {
        // truncate(-0.0) == -0.0 (IEEE 754 符号保持)
        let result = doubleFromBits(kk_math_truncate(doubleToBits(-0.0)))
        #expect(result == 0.0)
        #expect(result.sign == .minus)
    }

    @Test
    func testTruncateDoublePositiveZeroSign() {
        // truncate(+0.0) == +0.0 (符号保持; -0.0 と対称)
        let result = doubleFromBits(kk_math_truncate(doubleToBits(0.0)))
        #expect(result == 0.0)
        #expect(!(result.sign == .minus))
    }

    @Test
    func testTruncateFloatNegativeZero() {
        let result = floatFromBits(kk_math_truncate_float(floatToBits(-0.0)))
        #expect(result == 0.0)
        #expect(result.sign == .minus)
    }

    // MARK: - ceil / floor Float special values

    @Test
    func testCeilFloatNaN() {
        #expect(floatFromBits(kk_math_ceil_float(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testCeilFloatInfinity() {
        #expect(floatFromBits(kk_math_ceil_float(floatToBits(Float.infinity))).isInfinite)
        #expect(floatFromBits(kk_math_ceil_float(floatToBits(-Float.infinity))).isInfinite)
    }

    @Test
    func testFloorFloatNaN() {
        #expect(floatFromBits(kk_math_floor_float(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testFloorFloatInfinity() {
        #expect(floatFromBits(kk_math_floor_float(floatToBits(Float.infinity))).isInfinite)
        #expect(floatFromBits(kk_math_floor_float(floatToBits(-Float.infinity))).isInfinite)
    }

    @Test
    func testFloorFloatNegativeZero() {
        let result = floatFromBits(kk_math_floor_float(floatToBits(-0.0)))
        #expect(result == 0.0)
        #expect(result.sign == .minus)
    }

    // MARK: - round(Double) special values

    @Test
    func testRoundDoubleInfinity() {
        #expect(doubleFromBits(kk_math_round(doubleToBits(Double.infinity))).isInfinite)
        #expect(doubleFromBits(kk_math_round(doubleToBits(-Double.infinity))).isInfinite)
    }

    @Test
    func testRoundDoubleNegativeZero() {
        let result = doubleFromBits(kk_math_round(doubleToBits(-0.0)))
        #expect(result == 0.0)
    }

    // MARK: - round(Float) special values

    @Test
    func testRoundFloatInfinity() {
        #expect(floatFromBits(kk_math_round_float(floatToBits(Float.infinity))).isInfinite)
        #expect(floatFromBits(kk_math_round_float(floatToBits(-Float.infinity))).isInfinite)
    }

    // MARK: - sign(Double) edge cases

    @Test
    func testSignDoubleNegativeZero() {
        // Kotlin: sign(-0.0) == -0.0
        let result = doubleFromBits(kk_math_sign(doubleToBits(-0.0)))
        #expect(result == 0.0)
        #expect(result.sign == .minus)
    }

    @Test
    func testSignDoublePositiveInfinity() {
        #expect(doubleFromBits(kk_math_sign(doubleToBits(Double.infinity))) == 1.0)
    }

    @Test
    func testSignDoubleNegativeInfinity() {
        #expect(doubleFromBits(kk_math_sign(doubleToBits(-Double.infinity))) == -1.0)
    }

    @Test
    func testSignDoubleNaN() {
        #expect(doubleFromBits(kk_math_sign(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testSignDoublePositiveZero() {
        // sign(+0.0) == +0.0 (符号保持; -0.0 と対称)
        let result = doubleFromBits(kk_math_sign(doubleToBits(0.0)))
        #expect(result == 0.0)
        #expect(!(result.sign == .minus))
    }

    // MARK: - sign(Float) edge cases

    @Test
    func testSignFloatNegativeZero() {
        let result = floatFromBits(kk_math_sign_float(floatToBits(-0.0)))
        #expect(result == 0.0)
        #expect(result.sign == .minus)
    }

    @Test
    func testSignFloatPositiveInfinity() {
        #expect(floatFromBits(kk_math_sign_float(floatToBits(Float.infinity))) == 1.0)
    }

    @Test
    func testSignFloatNegativeInfinity() {
        #expect(floatFromBits(kk_math_sign_float(floatToBits(-Float.infinity))) == -1.0)
    }

    @Test
    func testSignFloatNaN() {
        #expect(floatFromBits(kk_math_sign_float(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testSignFloatPositiveZero() {
        let result = floatFromBits(kk_math_sign_float(floatToBits(0.0)))
        #expect(result == 0.0)
        #expect(!(result.sign == .minus))
    }

    // MARK: - hypot(Double) special cases

    @Test
    func testHypotDoubleInfinity() {
        // hypot(Inf, NaN) == Inf (IEEE 754 mandates this)
        let result = doubleFromBits(kk_math_hypot(doubleToBits(Double.infinity), doubleToBits(Double.nan)))
        #expect(result.isInfinite)
    }

    @Test
    func testHypotDoubleBothInfinity() {
        let result = doubleFromBits(kk_math_hypot(doubleToBits(Double.infinity), doubleToBits(Double.infinity)))
        #expect(result.isInfinite)
    }

    @Test
    func testHypotDoubleNaN() {
        #expect(doubleFromBits(kk_math_hypot(doubleToBits(Double.nan), doubleToBits(0.0))).isNaN)
    }

    @Test
    func testHypotDoubleZeros() {
        #expect(doubleFromBits(kk_math_hypot(doubleToBits(0.0), doubleToBits(0.0))) == 0.0)
    }

    // MARK: - hypot(Float) special cases

    @Test
    func testHypotFloatInfinity() {
        let result = floatFromBits(kk_math_hypot_float(floatToBits(Float.infinity), floatToBits(Float.nan)))
        #expect(result.isInfinite)
    }

    @Test
    func testHypotFloatNaN() {
        #expect(floatFromBits(kk_math_hypot_float(floatToBits(Float.nan), floatToBits(0.0))).isNaN)
    }

    // MARK: - exp(Double) edge cases

    @Test
    func testExpDoubleNaN() {
        #expect(doubleFromBits(kk_math_exp(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testExpDoublePositiveInfinity() {
        #expect(doubleFromBits(kk_math_exp(doubleToBits(Double.infinity))).isInfinite)
    }

    @Test
    func testExpDoubleNegativeInfinity() {
        // exp(-Inf) == 0
        #expect(doubleFromBits(kk_math_exp(doubleToBits(-Double.infinity))) == 0.0)
    }

    // MARK: - exp(Float) edge cases

    @Test
    func testExpFloatNaN() {
        #expect(floatFromBits(kk_math_exp_float(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testExpFloatPositiveInfinity() {
        #expect(floatFromBits(kk_math_exp_float(floatToBits(Float.infinity))).isInfinite)
    }

    @Test
    func testExpFloatNegativeInfinity() {
        #expect(floatFromBits(kk_math_exp_float(floatToBits(-Float.infinity))) == 0.0)
    }

    // MARK: - ln(Double) edge cases

    @Test
    func testLnDoubleZero() {
        // ln(0) == -Inf
        let result = doubleFromBits(kk_math_ln(doubleToBits(0.0)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    @Test
    func testLnDoubleNegative() {
        #expect(doubleFromBits(kk_math_ln(doubleToBits(-1.0))).isNaN)
    }

    @Test
    func testLnDoubleNaN() {
        #expect(doubleFromBits(kk_math_ln(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testLnDoubleInfinity() {
        #expect(doubleFromBits(kk_math_ln(doubleToBits(Double.infinity))).isInfinite)
        #expect(doubleFromBits(kk_math_ln(doubleToBits(Double.infinity))) > 0)
    }

    // MARK: - ln(Float) edge cases

    @Test
    func testLnFloatZero() {
        let result = floatFromBits(kk_math_ln_float(floatToBits(0.0)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    @Test
    func testLnFloatNegative() {
        #expect(floatFromBits(kk_math_ln_float(floatToBits(-1.0))).isNaN)
    }

    @Test
    func testLnFloatNaN() {
        #expect(floatFromBits(kk_math_ln_float(floatToBits(Float.nan))).isNaN)
    }

    // MARK: - log2 / log10 edge cases (Double)

    @Test
    func testLog2DoubleOne() {
        #expect(doubleFromBits(kk_math_log2(doubleToBits(1.0))) == 0.0)
    }

    @Test
    func testLog2DoubleNaN() {
        #expect(doubleFromBits(kk_math_log2(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testLog10DoubleOne() {
        #expect(doubleFromBits(kk_math_log10(doubleToBits(1.0))) == 0.0)
    }

    @Test
    func testLog10DoubleNaN() {
        #expect(doubleFromBits(kk_math_log10(doubleToBits(Double.nan))).isNaN)
    }

    // MARK: - log2 / log10 additional domain edge cases (Double)

    @Test
    func testLog2DoubleZero() {
        // log2(0) == -Inf  (IEEE 754: log of zero is -Inf)
        let result = doubleFromBits(kk_math_log2(doubleToBits(0.0)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    @Test
    func testLog2DoubleNegative() {
        // log2 of a negative number is NaN
        #expect(doubleFromBits(kk_math_log2(doubleToBits(-1.0))).isNaN)
    }

    @Test
    func testLog2DoublePositiveInfinity() {
        // log2(+Inf) == +Inf
        let result = doubleFromBits(kk_math_log2(doubleToBits(Double.infinity)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    @Test
    func testLog10DoubleZero() {
        // log10(0) == -Inf
        let result = doubleFromBits(kk_math_log10(doubleToBits(0.0)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    @Test
    func testLog10DoubleNegative() {
        // log10 of a negative number is NaN
        #expect(doubleFromBits(kk_math_log10(doubleToBits(-1.0))).isNaN)
    }

    @Test
    func testLog10DoublePositiveInfinity() {
        // log10(+Inf) == +Inf
        let result = doubleFromBits(kk_math_log10(doubleToBits(Double.infinity)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    // MARK: - log2 / log10 edge cases (Float)

    @Test
    func testLog2FloatOne() {
        #expect(floatFromBits(kk_math_log2_float(floatToBits(1.0))) == 0.0)
    }

    @Test
    func testLog10FloatOne() {
        #expect(floatFromBits(kk_math_log10_float(floatToBits(1.0))) == 0.0)
    }

    // MARK: - log2 / log10 additional domain edge cases (Float)

    @Test
    func testLog2FloatZero() {
        // log2(0.0f) == -Inf
        let result = floatFromBits(kk_math_log2_float(floatToBits(0.0)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    @Test
    func testLog2FloatNaN() {
        #expect(floatFromBits(kk_math_log2_float(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testLog2FloatNegative() {
        // log2 of a negative Float is NaN
        #expect(floatFromBits(kk_math_log2_float(floatToBits(-1.0))).isNaN)
    }

    @Test
    func testLog2FloatPositiveInfinity() {
        // log2(+Inf) == +Inf
        let result = floatFromBits(kk_math_log2_float(floatToBits(Float.infinity)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    @Test
    func testLog10FloatZero() {
        // log10(0.0f) == -Inf
        let result = floatFromBits(kk_math_log10_float(floatToBits(0.0)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    @Test
    func testLog10FloatNaN() {
        #expect(floatFromBits(kk_math_log10_float(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testLog10FloatNegative() {
        // log10 of a negative Float is NaN
        #expect(floatFromBits(kk_math_log10_float(floatToBits(-1.0))).isNaN)
    }

    @Test
    func testLog10FloatPositiveInfinity() {
        // log10(+Inf) == +Inf
        let result = floatFromBits(kk_math_log10_float(floatToBits(Float.infinity)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    // MARK: - log(x, base) domain edge cases (Double)
    // Kotlin defines explicit special cases for invalid bases and zero / infinity inputs.

    @Test
    func testLogDoubleNegativeX() {
        // ln of a negative number is NaN; NaN / finite == NaN
        #expect(doubleFromBits(kk_math_log(doubleToBits(-1.0), doubleToBits(2.0))).isNaN)
    }

    @Test
    func testLogDoubleZeroX() {
        // ln(0) == -Inf; -Inf / positive_finite == -Inf
        let result = doubleFromBits(kk_math_log(doubleToBits(0.0), doubleToBits(2.0)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    @Test
    func testLogDoubleNegativeBase() {
        // ln of a negative base is NaN; finite / NaN == NaN
        #expect(doubleFromBits(kk_math_log(doubleToBits(4.0), doubleToBits(-2.0))).isNaN)
    }

    @Test
    func testLogDoubleZeroBase() {
        // b <= 0 is invalid for kotlin.math.log(x, base)
        #expect(doubleFromBits(kk_math_log(doubleToBits(4.0), doubleToBits(0.0))).isNaN)
    }

    @Test
    func testLogDoubleBaseOneXEqualsOne() {
        // base == 1 is invalid for kotlin.math.log(x, base)
        #expect(doubleFromBits(kk_math_log(doubleToBits(1.0), doubleToBits(1.0))).isNaN)
    }

    @Test
    func testLogDoubleBaseOneXGreaterThanOneIsNaN() {
        // base == 1 remains NaN regardless of x
        #expect(doubleFromBits(kk_math_log(doubleToBits(2.0), doubleToBits(1.0))).isNaN)
    }

    @Test
    func testLogDoublePositiveInfinityX() {
        // ln(+Inf) / ln(2) == +Inf / positive_finite == +Inf
        let result = doubleFromBits(kk_math_log(doubleToBits(Double.infinity), doubleToBits(2.0)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    @Test
    func testLogDoubleNaNX() {
        #expect(doubleFromBits(kk_math_log(doubleToBits(Double.nan), doubleToBits(2.0))).isNaN)
    }

    @Test
    func testLogDoubleNaNBase() {
        #expect(doubleFromBits(kk_math_log(doubleToBits(4.0), doubleToBits(Double.nan))).isNaN)
    }

    // MARK: - log(x, base) domain edge cases (Float)

    @Test
    func testLogFloatNegativeX() {
        #expect(floatFromBits(kk_math_log_float(floatToBits(-1.0), floatToBits(2.0))).isNaN)
    }

    @Test
    func testLogFloatZeroX() {
        // ln(0.0f) / ln(2.0f) == -Inf
        let result = floatFromBits(kk_math_log_float(floatToBits(0.0), floatToBits(2.0)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    @Test
    func testLogFloatNegativeBase() {
        #expect(floatFromBits(kk_math_log_float(floatToBits(4.0), floatToBits(-2.0))).isNaN)
    }

    @Test
    func testLogFloatZeroBase() {
        // b <= 0 is invalid for kotlin.math.log(x, base)
        #expect(floatFromBits(kk_math_log_float(floatToBits(4.0), floatToBits(0.0))).isNaN)
    }

    @Test
    func testLogFloatBaseOneXEqualsOne() {
        // base == 1 is invalid for kotlin.math.log(x, base)
        #expect(floatFromBits(kk_math_log_float(floatToBits(1.0), floatToBits(1.0))).isNaN)
    }

    @Test
    func testLogFloatBaseOneXGreaterThanOneIsNaN() {
        // base == 1 remains NaN regardless of x
        #expect(floatFromBits(kk_math_log_float(floatToBits(2.0), floatToBits(1.0))).isNaN)
    }

    @Test
    func testLogFloatPositiveInfinityX() {
        let result = floatFromBits(kk_math_log_float(floatToBits(Float.infinity), floatToBits(2.0)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    @Test
    func testLogFloatNaNX() {
        #expect(floatFromBits(kk_math_log_float(floatToBits(Float.nan), floatToBits(2.0))).isNaN)
    }

    // MARK: - Double trig NaN / Inf propagation

    @Test
    func testSinDoubleNaN() {
        #expect(doubleFromBits(kk_math_sin(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testSinDoubleInfinity() {
        // sin(Inf) is undefined, should be NaN
        #expect(doubleFromBits(kk_math_sin(doubleToBits(Double.infinity))).isNaN)
    }

    @Test
    func testCosDoubleNaN() {
        #expect(doubleFromBits(kk_math_cos(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testCosDoubleInfinity() {
        #expect(doubleFromBits(kk_math_cos(doubleToBits(Double.infinity))).isNaN)
    }

    @Test
    func testTanDoubleNaN() {
        #expect(doubleFromBits(kk_math_tan(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testTanDoubleInfinity() {
        // tan(±Inf) は未定義 → NaN (sin/cos と同じパターン)
        #expect(doubleFromBits(kk_math_tan(doubleToBits(Double.infinity))).isNaN)
        #expect(doubleFromBits(kk_math_tan(doubleToBits(-Double.infinity))).isNaN)
    }

    @Test
    func testAsinDoubleOutOfRange() {
        // asin(x) for |x| > 1 is NaN
        #expect(doubleFromBits(kk_math_asin(doubleToBits(2.0))).isNaN)
        #expect(doubleFromBits(kk_math_asin(doubleToBits(-2.0))).isNaN)
    }

    @Test
    func testAcosDoubleOutOfRange() {
        // acos(x) for |x| > 1 is NaN
        #expect(doubleFromBits(kk_math_acos(doubleToBits(2.0))).isNaN)
    }

    @Test
    func testAtanDoubleInfinity() {
        // atan(+Inf) == pi/2
        let result = doubleFromBits(kk_math_atan(doubleToBits(Double.infinity)))
        #expect(abs((result) - (Double.pi / 2)) <= 1e-12)
    }

    @Test
    func testAtanDoubleNegativeInfinity() {
        // atan(-Inf) == -pi/2
        let result = doubleFromBits(kk_math_atan(doubleToBits(-Double.infinity)))
        #expect(abs((result) - (-Double.pi / 2)) <= 1e-12)
    }

    @Test
    func testAtan2DoubleSpecialCases() {
        // atan2(0, 0) == 0
        #expect(doubleFromBits(kk_math_atan2(doubleToBits(0.0), doubleToBits(0.0))) == 0.0)
        // atan2(+Inf, +Inf) == pi/4
        let result = doubleFromBits(kk_math_atan2(doubleToBits(Double.infinity), doubleToBits(Double.infinity)))
        #expect(abs((result) - (Double.pi / 4)) <= 1e-12)
    }

    @Test
    func testAtan2DoubleSignedZeroY() {
        // atan2(-0.0, +x) == -0.0 (符号付きゼロの通過)
        let result = doubleFromBits(kk_math_atan2(doubleToBits(-0.0), doubleToBits(1.0)))
        #expect(result == 0.0)
        #expect(result.sign == .minus)
    }

    @Test
    func testAtan2DoubleNegativeXAxis() {
        // atan2(+0, -x) == +π  /  atan2(-0, -x) == -π
        #expect(abs((doubleFromBits(kk_math_atan2(doubleToBits(0.0),  doubleToBits(-1.0)))) - (Double.pi)) <= 1e-12)
        #expect(abs((doubleFromBits(kk_math_atan2(doubleToBits(-0.0), doubleToBits(-1.0)))) - (-Double.pi)) <= 1e-12)
    }

    @Test
    func testAtan2DoubleYInfinityXFinite() {
        // atan2(+Inf, finite) == +π/2  /  atan2(-Inf, finite) == -π/2
        #expect(abs((doubleFromBits(kk_math_atan2(doubleToBits( Double.infinity), doubleToBits(1.0)))) - (Double.pi / 2)) <= 1e-12)
        #expect(abs((doubleFromBits(kk_math_atan2(doubleToBits(-Double.infinity), doubleToBits(1.0)))) - (-Double.pi / 2)) <= 1e-12)
    }

    @Test
    func testAtan2DoubleXInfinity() {
        // atan2(±y, +Inf) == ±0
        let posZero = doubleFromBits(kk_math_atan2(doubleToBits(1.0),  doubleToBits(Double.infinity)))
        #expect(abs((posZero) - (0.0)) <= 1e-12)
        let negZero = doubleFromBits(kk_math_atan2(doubleToBits(-1.0), doubleToBits(Double.infinity)))
        #expect(abs((negZero) - (0.0)) <= 1e-12)
        #expect(negZero.sign == .minus)
        // atan2(±y, -Inf) == ±π
        #expect(abs((doubleFromBits(kk_math_atan2(doubleToBits(1.0),  doubleToBits(-Double.infinity)))) - (Double.pi)) <= 1e-12)
        #expect(abs((doubleFromBits(kk_math_atan2(doubleToBits(-1.0), doubleToBits(-Double.infinity)))) - (-Double.pi)) <= 1e-12)
    }

    @Test
    func testAtan2DoubleNaN() {
        #expect(doubleFromBits(kk_math_atan2(doubleToBits(Double.nan), doubleToBits(1.0))).isNaN)
        #expect(doubleFromBits(kk_math_atan2(doubleToBits(1.0), doubleToBits(Double.nan))).isNaN)
    }

    // MARK: - atan2 IEEE 754 完全テーブル補完 (TEST-MATH-024)

    @Test
    func testAtan2DoubleSignedZeroPositiveZeroX() {
        // IEEE 754: atan2(+0, +0) == +0 (符号は正)
        let pos = doubleFromBits(kk_math_atan2(doubleToBits(0.0), doubleToBits(0.0)))
        #expect(pos == 0.0)
        #expect(!(pos.sign == .minus))
        // IEEE 754: atan2(-0, +0) == -0 (符号は負)
        let neg = doubleFromBits(kk_math_atan2(doubleToBits(-0.0), doubleToBits(0.0)))
        #expect(neg == 0.0)
        #expect(neg.sign == .minus)
    }

    @Test
    func testAtan2DoubleSignedZeroNegativeZeroX() {
        // IEEE 754: atan2(+0, -0) == +π
        #expect(abs((doubleFromBits(kk_math_atan2(doubleToBits(0.0), doubleToBits(-0.0)))) - (Double.pi)) <= 1e-12)
        // IEEE 754: atan2(-0, -0) == -π
        #expect(abs((doubleFromBits(kk_math_atan2(doubleToBits(-0.0), doubleToBits(-0.0)))) - (-Double.pi)) <= 1e-12)
    }

    @Test
    func testAtan2DoubleZeroYAtInfinityX() {
        // IEEE 754: atan2(+0, +Inf) == +0 (符号は正)
        let posAtPosInf = doubleFromBits(kk_math_atan2(doubleToBits(0.0), doubleToBits(Double.infinity)))
        #expect(posAtPosInf == 0.0)
        #expect(!(posAtPosInf.sign == .minus))
        // IEEE 754: atan2(-0, +Inf) == -0 (符号は負)
        let negAtPosInf = doubleFromBits(kk_math_atan2(doubleToBits(-0.0), doubleToBits(Double.infinity)))
        #expect(negAtPosInf == 0.0)
        #expect(negAtPosInf.sign == .minus)
        // IEEE 754: atan2(+0, -Inf) == +π
        #expect(abs((doubleFromBits(kk_math_atan2(doubleToBits(0.0), doubleToBits(-Double.infinity)))) - (Double.pi)) <= 1e-12)
        // IEEE 754: atan2(-0, -Inf) == -π
        #expect(abs((doubleFromBits(kk_math_atan2(doubleToBits(-0.0), doubleToBits(-Double.infinity)))) - (-Double.pi)) <= 1e-12)
    }

    @Test
    func testAtan2DoubleInfinityBothArgs() {
        // IEEE 754: atan2(-Inf, +Inf) == -π/4
        #expect(abs((doubleFromBits(kk_math_atan2(doubleToBits(-Double.infinity), doubleToBits(Double.infinity)))) - (-Double.pi / 4)) <= 1e-12)
        // IEEE 754: atan2(+Inf, -Inf) == +3π/4
        #expect(abs((doubleFromBits(kk_math_atan2(doubleToBits(Double.infinity), doubleToBits(-Double.infinity)))) - (3 * Double.pi / 4)) <= 1e-12)
        // IEEE 754: atan2(-Inf, -Inf) == -3π/4
        #expect(abs((doubleFromBits(kk_math_atan2(doubleToBits(-Double.infinity), doubleToBits(-Double.infinity)))) - (-3 * Double.pi / 4)) <= 1e-12)
    }

    // MARK: - Float trig NaN / Inf propagation

    @Test
    func testSinFloatNaN() {
        #expect(floatFromBits(kk_math_sin_float(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testSinFloatInfinity() {
        #expect(floatFromBits(kk_math_sin_float(floatToBits(Float.infinity))).isNaN)
    }

    @Test
    func testCosFloatNaN() {
        #expect(floatFromBits(kk_math_cos_float(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testAsinFloatOutOfRange() {
        #expect(floatFromBits(kk_math_asin_float(floatToBits(2.0))).isNaN)
    }

    @Test
    func testAcosFloatOutOfRange() {
        #expect(floatFromBits(kk_math_acos_float(floatToBits(2.0))).isNaN)
    }

    @Test
    func testTanFloatInfinity() {
        #expect(floatFromBits(kk_math_tan_float(floatToBits(Float.infinity))).isNaN)
        #expect(floatFromBits(kk_math_tan_float(floatToBits(-Float.infinity))).isNaN)
    }

    // MARK: - atan2(Float) IEEE 754 edge cases (TEST-MATH-024)

    @Test
    func testAtan2FloatNaN() {
        #expect(floatFromBits(kk_math_atan2_float(floatToBits(Float.nan), floatToBits(1.0))).isNaN)
        #expect(floatFromBits(kk_math_atan2_float(floatToBits(1.0), floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testAtan2FloatInfinityXFinite() {
        // atan2(+Inf, finite) == +π/2
        let posHalfPi = floatFromBits(kk_math_atan2_float(floatToBits(Float.infinity), floatToBits(1.0)))
        #expect(abs((posHalfPi) - (Float.pi / 2)) <= 1e-6)
        // atan2(-Inf, finite) == -π/2 (奇関数の対称性)
        let negHalfPi = floatFromBits(kk_math_atan2_float(floatToBits(-Float.infinity), floatToBits(1.0)))
        #expect(abs((negHalfPi) - (-Float.pi / 2)) <= 1e-6)
    }

    @Test
    func testAtan2FloatSignedZero() {
        // IEEE 754: atan2(-0, +0) == -0 (符号保持)
        let result = floatFromBits(kk_math_atan2_float(floatToBits(-0.0), floatToBits(0.0)))
        #expect(result == 0.0)
        #expect(result.sign == .minus)
    }

    @Test
    func testAtan2FloatInfinityBothArgs() {
        // IEEE 754: atan2(-Inf, +Inf) == -π/4
        #expect(abs((floatFromBits(kk_math_atan2_float(floatToBits(-Float.infinity), floatToBits(Float.infinity)))) - (-Float.pi / 4)) <= 1e-6)
        // IEEE 754: atan2(+Inf, -Inf) == +3π/4
        #expect(abs((floatFromBits(kk_math_atan2_float(floatToBits(Float.infinity), floatToBits(-Float.infinity)))) - (3 * Float.pi / 4)) <= 1e-6)
        // IEEE 754: atan2(-Inf, -Inf) == -3π/4
        #expect(abs((floatFromBits(kk_math_atan2_float(floatToBits(-Float.infinity), floatToBits(-Float.infinity)))) - (-3 * Float.pi / 4)) <= 1e-6)
    }

    // MARK: - Hyperbolic functions (Double)

    @Test
    func testSinhDoubleZero() {
        #expect(abs((doubleFromBits(kk_math_sinh(doubleToBits(0.0)))) - (0.0)) <= 1e-12)
    }

    @Test
    func testSinhDoubleInfinity() {
        #expect(doubleFromBits(kk_math_sinh(doubleToBits(Double.infinity))).isInfinite)
    }

    @Test
    func testSinhDoubleNegativeInfinity() {
        // sinh は奇関数: sinh(-Inf) == -Inf
        let result = doubleFromBits(kk_math_sinh(doubleToBits(-Double.infinity)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    @Test
    func testSinhDoubleNaN() {
        #expect(doubleFromBits(kk_math_sinh(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testCoshDoubleZero() {
        #expect(abs((doubleFromBits(kk_math_cosh(doubleToBits(0.0)))) - (1.0)) <= 1e-12)
    }

    @Test
    func testCoshDoubleInfinity() {
        #expect(doubleFromBits(kk_math_cosh(doubleToBits(Double.infinity))).isInfinite)
    }

    @Test
    func testCoshDoubleNegativeInfinity() {
        // cosh は偶関数: cosh(-Inf) == +Inf
        let result = doubleFromBits(kk_math_cosh(doubleToBits(-Double.infinity)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    @Test
    func testCoshDoubleNaN() {
        #expect(doubleFromBits(kk_math_cosh(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testTanhDoubleZero() {
        #expect(abs((doubleFromBits(kk_math_tanh(doubleToBits(0.0)))) - (0.0)) <= 1e-12)
    }

    @Test
    func testTanhDoubleInfinity() {
        // tanh(+Inf) == 1.0
        #expect(abs((doubleFromBits(kk_math_tanh(doubleToBits(Double.infinity)))) - (1.0)) <= 1e-12)
    }

    @Test
    func testTanhDoubleNegativeInfinity() {
        // tanh は奇関数: tanh(-Inf) == -1.0
        #expect(abs((doubleFromBits(kk_math_tanh(doubleToBits(-Double.infinity)))) - (-1.0)) <= 1e-12)
    }

    @Test
    func testTanhDoubleNaN() {
        #expect(doubleFromBits(kk_math_tanh(doubleToBits(Double.nan))).isNaN)
    }

    // MARK: - Hyperbolic functions (Float)

    @Test
    func testSinhFloatZero() {
        #expect(abs((floatFromBits(kk_math_sinh_float(floatToBits(0.0)))) - (0.0)) <= 1e-6)
    }

    @Test
    func testSinhFloatNaN() {
        #expect(floatFromBits(kk_math_sinh_float(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testSinhFloatNegativeInfinity() {
        let result = floatFromBits(kk_math_sinh_float(floatToBits(-Float.infinity)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    @Test
    func testCoshFloatZero() {
        #expect(abs((floatFromBits(kk_math_cosh_float(floatToBits(0.0)))) - (1.0)) <= 1e-6)
    }

    @Test
    func testCoshFloatNaN() {
        #expect(floatFromBits(kk_math_cosh_float(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testCoshFloatNegativeInfinity() {
        // cosh は偶関数: cosh(-Inf) == +Inf
        let result = floatFromBits(kk_math_cosh_float(floatToBits(-Float.infinity)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    @Test
    func testTanhFloatInfinity() {
        #expect(abs((floatFromBits(kk_math_tanh_float(floatToBits(Float.infinity)))) - (1.0)) <= 1e-6)
    }

    @Test
    func testTanhFloatNegativeInfinity() {
        #expect(abs((floatFromBits(kk_math_tanh_float(floatToBits(-Float.infinity)))) - (-1.0)) <= 1e-6)
    }

    @Test
    func testTanhFloatNaN() {
        #expect(floatFromBits(kk_math_tanh_float(floatToBits(Float.nan))).isNaN)
    }

    // MARK: - Inverse hyperbolic functions (Double)

    @Test
    func testAcoshDoubleOne() {
        // acosh(1) == 0
        #expect(abs((doubleFromBits(kk_math_acosh(doubleToBits(1.0)))) - (0.0)) <= 1e-12)
    }

    @Test
    func testAcoshDoubleOutOfRange() {
        // acosh(x) for x < 1 is NaN
        #expect(doubleFromBits(kk_math_acosh(doubleToBits(0.5))).isNaN)
    }

    @Test
    func testAcoshDoubleInfinity() {
        #expect(doubleFromBits(kk_math_acosh(doubleToBits(Double.infinity))).isInfinite)
    }

    @Test
    func testAsinhDoubleZero() {
        #expect(abs((doubleFromBits(kk_math_asinh(doubleToBits(0.0)))) - (0.0)) <= 1e-12)
    }

    @Test
    func testAsinhDoubleNaN() {
        #expect(doubleFromBits(kk_math_asinh(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testAtanhDoubleZero() {
        #expect(abs((doubleFromBits(kk_math_atanh(doubleToBits(0.0)))) - (0.0)) <= 1e-12)
    }

    @Test
    func testAtanhDoubleOutOfRange() {
        // atanh(x) for |x| > 1 is NaN
        #expect(doubleFromBits(kk_math_atanh(doubleToBits(2.0))).isNaN)
    }

    @Test
    func testAtanhDoubleOne() {
        // atanh(1) == +Inf
        #expect(doubleFromBits(kk_math_atanh(doubleToBits(1.0))).isInfinite)
    }

    @Test
    func testAtanhDoubleNegativeOne() {
        // atanh は奇関数: atanh(-1) == -Inf
        let result = doubleFromBits(kk_math_atanh(doubleToBits(-1.0)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    // MARK: - Inverse hyperbolic functions (Float)

    @Test
    func testAcoshFloatOne() {
        #expect(abs((floatFromBits(kk_math_acosh_float(floatToBits(1.0)))) - (0.0)) <= 1e-6)
    }

    @Test
    func testAcoshFloatOutOfRange() {
        #expect(floatFromBits(kk_math_acosh_float(floatToBits(0.5))).isNaN)
    }

    @Test
    func testAsinhFloatZero() {
        #expect(abs((floatFromBits(kk_math_asinh_float(floatToBits(0.0)))) - (0.0)) <= 1e-6)
    }

    @Test
    func testAtanhFloatOne() {
        #expect(floatFromBits(kk_math_atanh_float(floatToBits(1.0))).isInfinite)
    }

    @Test
    func testAtanhFloatNegativeOne() {
        let result = floatFromBits(kk_math_atanh_float(floatToBits(-1.0)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    // MARK: - cbrt(Double) edge cases

    @Test
    func testCbrtDoubleNegative() {
        // cbrt(-8) == -2
        #expect(abs((doubleFromBits(kk_math_cbrt(doubleToBits(-8.0)))) - (-2.0)) <= 1e-12)
    }

    @Test
    func testCbrtDoubleZero() {
        #expect(doubleFromBits(kk_math_cbrt(doubleToBits(0.0))) == 0.0)
    }

    @Test
    func testCbrtDoubleNaN() {
        #expect(doubleFromBits(kk_math_cbrt(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testCbrtDoubleInfinity() {
        #expect(doubleFromBits(kk_math_cbrt(doubleToBits(Double.infinity))).isInfinite)
    }

    @Test
    func testCbrtDoubleNegativeZero() {
        // cbrt は奇関数: cbrt(-0.0) == -0.0
        let result = doubleFromBits(kk_math_cbrt(doubleToBits(-0.0)))
        #expect(result == 0.0)
        #expect(result.sign == .minus)
    }

    @Test
    func testCbrtDoubleNegativeInfinity() {
        // cbrt(-Inf) == -Inf
        let result = doubleFromBits(kk_math_cbrt(doubleToBits(-Double.infinity)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    // MARK: - cbrt(Float) edge cases

    @Test
    func testCbrtFloatNegative() {
        #expect(abs((floatFromBits(kk_math_cbrt_float(floatToBits(-8.0)))) - (-2.0)) <= 1e-6)
    }

    @Test
    func testCbrtFloatZero() {
        #expect(floatFromBits(kk_math_cbrt_float(floatToBits(0.0))) == 0.0)
    }

    @Test
    func testCbrtFloatNaN() {
        #expect(floatFromBits(kk_math_cbrt_float(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testCbrtFloatNegativeZero() {
        let result = floatFromBits(kk_math_cbrt_float(floatToBits(-0.0)))
        #expect(result == 0.0)
        #expect(result.sign == .minus)
    }

    @Test
    func testCbrtFloatInfinity() {
        // +Inf → +Inf, -Inf → -Inf
        #expect(floatFromBits(kk_math_cbrt_float(floatToBits(Float.infinity))).isInfinite)
        let neg = floatFromBits(kk_math_cbrt_float(floatToBits(-Float.infinity)))
        #expect(neg.isInfinite)
        #expect(neg < 0)
    }

    // MARK: - IEEErem (Double) edge cases

    @Test
    func testIEEEremDoubleBasic() {
        // IEEE remainder: 5.0 rem 3.0 == -1.0 (nearest-integer remainder)
        #expect(abs((doubleFromBits(kk_math_IEEErem(doubleToBits(5.0), doubleToBits(3.0)))) - (-1.0)) <= 1e-12)
    }

    @Test
    func testIEEEremDoubleNaN() {
        #expect(doubleFromBits(kk_math_IEEErem(doubleToBits(Double.nan), doubleToBits(1.0))).isNaN)
    }

    @Test
    func testIEEEremDoubleZeroDivisor() {
        #expect(doubleFromBits(kk_math_IEEErem(doubleToBits(5.0), doubleToBits(0.0))).isNaN)
    }

    // MARK: - IEEErem (Float) edge cases

    @Test
    func testIEEEremFloatBasic() {
        #expect(abs((floatFromBits(kk_math_IEEErem_float(floatToBits(5.0), floatToBits(3.0)))) - (-1.0)) <= 1e-6)
    }

    @Test
    func testIEEEremFloatNaN() {
        #expect(floatFromBits(kk_math_IEEErem_float(floatToBits(Float.nan), floatToBits(1.0))).isNaN)
    }

    // MARK: - withSign (copysign) edge cases

    @Test
    func testWithSignDoublePositiveSign() {
        // copysign(-3.0, +1.0) == +3.0
        #expect(doubleFromBits(kk_math_withSign(doubleToBits(-3.0), doubleToBits(1.0))) == 3.0)
    }

    @Test
    func testWithSignDoubleNegativeSign() {
        #expect(doubleFromBits(kk_math_withSign(doubleToBits(3.0), doubleToBits(-1.0))) == -3.0)
    }

    @Test
    func testWithSignDoubleNegativeZeroSign() {
        // Sign of -0.0 is negative
        let result = doubleFromBits(kk_math_withSign(doubleToBits(3.0), doubleToBits(-0.0)))
        #expect(result == -3.0)
    }

    @Test
    func testWithSignFloatPositiveSign() {
        #expect(floatFromBits(kk_math_withSign_float(floatToBits(-3.0), floatToBits(1.0))) == 3.0)
    }

    @Test
    func testWithSignFloatNegativeSign() {
        #expect(floatFromBits(kk_math_withSign_float(floatToBits(3.0), floatToBits(-1.0))) == -3.0)
    }

    @Test
    func testWithSignFloatIntSign() {
        #expect(floatFromBits(kk_math_withSign_float_int(floatToBits(-3.0), 1)) == 3.0)
        #expect(floatFromBits(kk_math_withSign_float_int(floatToBits(3.0), -1)) == -3.0)
    }

    // MARK: - nextTowards edge cases

    @Test
    func testNextTowardsDoubleUp() {
        // nextafter(1.0, +Inf) == 1.0.nextUp
        let result = doubleFromBits(kk_math_nextTowards(doubleToBits(1.0), doubleToBits(Double.infinity)))
        #expect(result == Double(1.0).nextUp)
    }

    @Test
    func testNextTowardsDoubleDown() {
        // nextafter(1.0, -Inf) == 1.0.nextDown
        let result = doubleFromBits(kk_math_nextTowards(doubleToBits(1.0), doubleToBits(-Double.infinity)))
        #expect(result == Double(1.0).nextDown)
    }

    @Test
    func testNextTowardsDoubleSame() {
        // nextafter(x, x) == x
        let result = doubleFromBits(kk_math_nextTowards(doubleToBits(1.0), doubleToBits(1.0)))
        #expect(result == 1.0)
    }

    @Test
    func testNextTowardsDoubleNaN() {
        #expect(doubleFromBits(kk_math_nextTowards(doubleToBits(Double.nan), doubleToBits(1.0))).isNaN)
    }

    @Test
    func testNextTowardsFloat() {
        #expect(floatFromBits(kk_math_nextTowards_float(floatToBits(1.0), floatToBits(Float.infinity))) == Float(1.0).nextUp)
        #expect(floatFromBits(kk_math_nextTowards_float(floatToBits(1.0), floatToBits(-Float.infinity))) == Float(1.0).nextDown)
        #expect(floatFromBits(kk_math_nextTowards_float(floatToBits(Float.nan), floatToBits(1.0))).isNaN)
    }

    // MARK: - ulp edge cases (Double)

    @Test
    func testUlpDoubleZero() {
        // ulp(0.0) == leastNonzeroMagnitude (subnormal)
        let result = doubleFromBits(kk_double_ulp(doubleToBits(0.0)))
        #expect(result == Double(0.0).ulp)
    }

    @Test
    func testUlpDoubleInfinity() {
        // ulp(Inf) == NaN (IEEE 754)
        let result = doubleFromBits(kk_double_ulp(doubleToBits(Double.infinity)))
        #expect(result.isNaN)
    }

    @Test
    func testUlpDoubleNaN() {
        #expect(doubleFromBits(kk_double_ulp(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testUlpDoubleNegativeInfinity() {
        // ulp(-Inf) == NaN (正の無限大と対称)
        #expect(doubleFromBits(kk_double_ulp(doubleToBits(-Double.infinity))).isNaN)
    }

    @Test
    func testUlpDoubleNegativeZero() {
        // ulp(-0.0) == ulp(+0.0) = leastNonzeroMagnitude (大きさのみ依存)
        let result = doubleFromBits(kk_double_ulp(doubleToBits(-0.0)))
        #expect(result == Double(0.0).ulp)
    }

    // MARK: - ulp edge cases (Float)

    @Test
    func testUlpFloatZero() {
        let result = floatFromBits(kk_float_ulp(floatToBits(0.0)))
        #expect(result == Float(0.0).ulp)
    }

    @Test
    func testUlpFloatInfinity() {
        // ulp(Inf) == NaN (IEEE 754)
        let result = floatFromBits(kk_float_ulp(floatToBits(Float.infinity)))
        #expect(result.isNaN)
    }

    @Test
    func testUlpFloatNaN() {
        #expect(floatFromBits(kk_float_ulp(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testUlpFloatNegativeInfinity() {
        #expect(floatFromBits(kk_float_ulp(floatToBits(-Float.infinity))).isNaN)
    }

    // MARK: - nextUp / nextDown at boundaries (Double)

    @Test
    func testNextUpDoubleMaxFinite() {
        // nextUp(Double.greatestFiniteMagnitude) == +Inf
        let result = doubleFromBits(kk_double_nextUp(doubleToBits(Double.greatestFiniteMagnitude)))
        #expect(result.isInfinite)
        #expect(result > 0)
    }

    @Test
    func testNextDownDoubleNegativeMaxFinite() {
        // nextDown(-Double.greatestFiniteMagnitude) == -Inf
        let result = doubleFromBits(kk_double_nextDown(doubleToBits(-Double.greatestFiniteMagnitude)))
        #expect(result.isInfinite)
        #expect(result < 0)
    }

    @Test
    func testNextUpDoubleNaN() {
        #expect(doubleFromBits(kk_double_nextUp(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testNextDownDoubleNaN() {
        #expect(doubleFromBits(kk_double_nextDown(doubleToBits(Double.nan))).isNaN)
    }

    @Test
    func testNextUpDoubleNegativeInfinity() {
        // nextUp(-Inf) == -Double.greatestFiniteMagnitude
        let result = doubleFromBits(kk_double_nextUp(doubleToBits(-Double.infinity)))
        #expect(result == -Double.greatestFiniteMagnitude)
    }

    @Test
    func testNextDownDoublePositiveInfinity() {
        // nextDown(+Inf) == Double.greatestFiniteMagnitude
        let result = doubleFromBits(kk_double_nextDown(doubleToBits(Double.infinity)))
        #expect(result == Double.greatestFiniteMagnitude)
    }

    // MARK: - nextUp / nextDown at boundaries (Float)

    @Test
    func testNextUpFloatMaxFinite() {
        let result = floatFromBits(kk_float_nextUp(floatToBits(Float.greatestFiniteMagnitude)))
        #expect(result.isInfinite)
    }

    @Test
    func testNextDownFloatNaN() {
        #expect(floatFromBits(kk_float_nextDown(floatToBits(Float.nan))).isNaN)
    }

    @Test
    func testNextUpFloatNegativeInfinity() {
        // nextUp(-Inf) == -Float.greatestFiniteMagnitude
        let result = floatFromBits(kk_float_nextUp(floatToBits(-Float.infinity)))
        #expect(result == -Float.greatestFiniteMagnitude)
    }

    @Test
    func testNextDownFloatPositiveInfinity() {
        // nextDown(+Inf) == Float.greatestFiniteMagnitude
        let result = floatFromBits(kk_float_nextDown(floatToBits(Float.infinity)))
        #expect(result == Float.greatestFiniteMagnitude)
    }

    // MARK: - Conversion edge cases

    @Test
    func testIntToLongNegative() {
        #expect(kk_int_to_long(Int(Int32.min)) == Int(Int32.min))
    }

    @Test
    func testLongToIntOverflow() {
        // Long value larger than Int32.max saturates? Actually kk_long_to_int wraps (truncates).
        let result = kk_long_to_int(Int(Int32.max) + 1)
        #expect(result == Int(Int32.min))
    }

    @Test
    func testLongToByteEdge() {
        #expect(kk_long_to_byte(127) == 127)
        #expect(kk_long_to_byte(128) == -128)
        #expect(kk_long_to_byte(-129) == 127)
    }

    @Test
    func testLongToShortEdge() {
        #expect(kk_long_to_short(32767) == 32767)
        #expect(kk_long_to_short(32768) == -32768)
    }

    @Test
    func testLongToFloatLargeValue() {
        // Very large long converted to float (precision loss expected, but no NaN/Inf)
        let result = floatFromBits(kk_long_to_float(Int(Int64.max)))
        #expect(!(result.isNaN))
        #expect(result > 0)
    }

    @Test
    func testLongToDoubleLargeValue() {
        let result = doubleFromBits(kk_long_to_double(Int(Int64.max)))
        #expect(!(result.isNaN))
        #expect(result > 0)
    }

    // MARK: - Double/Float to Int/Long conversion at boundary

    @Test
    func testDoubleToIntExactBoundary() {
        // Exactly Int32.max as double
        #expect(kk_double_to_int(doubleToBits(Double(Int32.max))) == Int(Int32.max))
    }

    @Test
    func testDoubleToIntNaN() {
        #expect(kk_double_to_int(doubleToBits(Double.nan)) == 0)
    }

    @Test
    func testDoubleToIntPositiveInfinity() {
        #expect(kk_double_to_int(doubleToBits(Double.infinity)) == Int(Int32.max))
    }

    @Test
    func testDoubleToIntNegativeInfinity() {
        #expect(kk_double_to_int(doubleToBits(-Double.infinity)) == Int(Int32.min))
    }

    @Test
    func testFloatToIntNaN() {
        #expect(kk_float_to_int(floatToBits(Float.nan)) == 0)
    }

    @Test
    func testFloatToIntPositiveInfinity() {
        #expect(kk_float_to_int(floatToBits(Float.infinity)) == Int(Int32.max))
    }

    @Test
    func testFloatToIntNegativeInfinity() {
        #expect(kk_float_to_int(floatToBits(-Float.infinity)) == Int(Int32.min))
    }

    @Test
    func testDoubleToLongNaN() {
        #expect(kk_double_to_long(doubleToBits(Double.nan)) == 0)
    }

    @Test
    func testDoubleToLongPositiveInfinity() {
        #expect(kk_double_to_long(doubleToBits(Double.infinity)) == Int(Int64.max))
    }

    @Test
    func testDoubleToLongNegativeInfinity() {
        #expect(kk_double_to_long(doubleToBits(-Double.infinity)) == Int(Int64.min))
    }
}
#endif
