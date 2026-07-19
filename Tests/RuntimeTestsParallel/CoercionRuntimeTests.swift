#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct CoercionRuntimeTests {

    // MARK: - Helpers

    private func doubleToBits(_ value: Double) -> Int { kk_double_to_bits(value) }
    private func floatToBits(_ value: Float) -> Int { kk_float_to_bits(value) }
    private func bitsToDouble(_ bits: Int) -> Double { kk_bits_to_double(bits) }
    private func bitsToFloat(_ bits: Int) -> Float { kk_bits_to_float(bits) }
    private func unsignedToBits(_ value: UInt) -> Int { Int(bitPattern: value) }
    private func bitsToUnsigned(_ bits: Int) -> UInt { UInt(bitPattern: bits) }

    // MARK: - Int Coercion Runtime Tests

    @Test
    func testIntCoerceInRuntimeBehavior() {
        #expect(kk_int_coerceIn(5, 1, 10) == 5)
        #expect(kk_int_coerceIn(0, 1, 10) == 1)
        #expect(kk_int_coerceIn(15, 1, 10) == 10)

        #expect(kk_int_coerceIn(1, 1, 10) == 1)
        #expect(kk_int_coerceIn(10, 1, 10) == 10)

        #expect(kk_int_coerceIn(-5, -10, -1) == -5)
        #expect(kk_int_coerceIn(-15, -10, -1) == -10)
        #expect(kk_int_coerceIn(5, -10, -1) == -1)
    }

    @Test
    func testIntCoerceAtLeastRuntimeBehavior() {
        #expect(kk_int_coerceAtLeast(5, 1) == 5)
        #expect(kk_int_coerceAtLeast(0, 1) == 1)
        #expect(kk_int_coerceAtLeast(1, 1) == 1)

        #expect(kk_int_coerceAtLeast(-5, -10) == -5)
        #expect(kk_int_coerceAtLeast(-15, -10) == -10)
    }

    @Test
    func testIntCoerceAtMostRuntimeBehavior() {
        #expect(kk_int_coerceAtMost(5, 10) == 5)
        #expect(kk_int_coerceAtMost(15, 10) == 10)
        #expect(kk_int_coerceAtMost(10, 10) == 10)

        #expect(kk_int_coerceAtMost(-5, -1) == -5)
        #expect(kk_int_coerceAtMost(-15, -1) == -15)
    }

    // MARK: - Long Coercion Runtime Tests

    @Test
    func testLongCoerceInRuntimeBehavior() {
        // Test normal coercion (Long uses same Int representation on 64-bit)
        #expect(kk_long_coerceIn(5000000000, 1000000000, 10000000000) == 5000000000)
        #expect(kk_long_coerceIn(500000000, 1000000000, 10000000000) == 1000000000)
        #expect(kk_long_coerceIn(15000000000, 1000000000, 10000000000) == 10000000000)

        #expect(kk_long_coerceIn(1000000000, 1000000000, 10000000000) == 1000000000)
        #expect(kk_long_coerceIn(10000000000, 1000000000, 10000000000) == 10000000000)
    }

    @Test
    func testLongCoerceAtLeastRuntimeBehavior() {
        #expect(kk_long_coerceAtLeast(5000000000, 1000000000) == 5000000000)
        #expect(kk_long_coerceAtLeast(500000000, 1000000000) == 1000000000)
        #expect(kk_long_coerceAtLeast(1000000000, 1000000000) == 1000000000)
    }

    @Test
    func testLongCoerceAtMostRuntimeBehavior() {
        #expect(kk_long_coerceAtMost(5000000000, 10000000000) == 5000000000)
        #expect(kk_long_coerceAtMost(15000000000, 10000000000) == 10000000000)
        #expect(kk_long_coerceAtMost(10000000000, 10000000000) == 10000000000)
    }

    // MARK: - Double Coercion Runtime Tests

    @Test
    func testDoubleCoerceInRuntimeBehavior() {
        let valueBits = doubleToBits(5.5)
        let minBits = doubleToBits(1.0)
        let maxBits = doubleToBits(10.0)

        let resultBits = kk_double_coerceIn(valueBits, minBits, maxBits)
        let result = bitsToDouble(resultBits)
        #expect(abs(result - 5.5) <= 1e-10)

        let belowBits = doubleToBits(0.5)
        let clampedBelowBits = kk_double_coerceIn(belowBits, minBits, maxBits)
        let clampedBelow = bitsToDouble(clampedBelowBits)
        #expect(abs(clampedBelow - 1.0) <= 1e-10)

        let aboveBits = doubleToBits(15.5)
        let clampedAboveBits = kk_double_coerceIn(aboveBits, minBits, maxBits)
        let clampedAbove = bitsToDouble(clampedAboveBits)
        #expect(abs(clampedAbove - 10.0) <= 1e-10)
    }

    @Test
    func testDoubleCoerceAtLeastRuntimeBehavior() {
        let valueBits = doubleToBits(5.5)
        let minBits = doubleToBits(1.0)

        let resultBits = kk_double_coerceAtLeast(valueBits, minBits)
        let result = bitsToDouble(resultBits)
        #expect(abs(result - 5.5) <= 1e-10)

        let belowBits = doubleToBits(0.5)
        let clampedBits = kk_double_coerceAtLeast(belowBits, minBits)
        let clamped = bitsToDouble(clampedBits)
        #expect(abs(clamped - 1.0) <= 1e-10)
    }

    @Test
    func testDoubleCoerceAtMostRuntimeBehavior() {
        let valueBits = doubleToBits(5.5)
        let maxBits = doubleToBits(10.0)

        let resultBits = kk_double_coerceAtMost(valueBits, maxBits)
        let result = bitsToDouble(resultBits)
        #expect(abs(result - 5.5) <= 1e-10)

        let aboveBits = doubleToBits(15.5)
        let clampedBits = kk_double_coerceAtMost(aboveBits, maxBits)
        let clamped = bitsToDouble(clampedBits)
        #expect(abs(clamped - 10.0) <= 1e-10)
    }

    // MARK: - Float Coercion Runtime Tests

    @Test
    func testFloatCoerceInRuntimeBehavior() {
        let valueBits = floatToBits(5.5)
        let minBits = floatToBits(1.0)
        let maxBits = floatToBits(10.0)

        let resultBits = kk_float_coerceIn(valueBits, minBits, maxBits)
        let result = bitsToFloat(resultBits)
        #expect(abs(result - 5.5) <= 1e-6)

        let belowBits = floatToBits(0.5)
        let clampedBelowBits = kk_float_coerceIn(belowBits, minBits, maxBits)
        let clampedBelow = bitsToFloat(clampedBelowBits)
        #expect(abs(clampedBelow - 1.0) <= 1e-6)

        let aboveBits = floatToBits(15.5)
        let clampedAboveBits = kk_float_coerceIn(aboveBits, minBits, maxBits)
        let clampedAbove = bitsToFloat(clampedAboveBits)
        #expect(abs(clampedAbove - 10.0) <= 1e-6)
    }

    @Test
    func testFloatCoerceAtLeastRuntimeBehavior() {
        let valueBits = floatToBits(5.5)
        let minBits = floatToBits(1.0)

        let resultBits = kk_float_coerceAtLeast(valueBits, minBits)
        let result = bitsToFloat(resultBits)
        #expect(abs(result - 5.5) <= 1e-6)

        let belowBits = floatToBits(0.5)
        let clampedBits = kk_float_coerceAtLeast(belowBits, minBits)
        let clamped = bitsToFloat(clampedBits)
        #expect(abs(clamped - 1.0) <= 1e-6)
    }

    @Test
    func testFloatCoerceAtMostRuntimeBehavior() {
        let valueBits = floatToBits(5.5)
        let maxBits = floatToBits(10.0)

        let resultBits = kk_float_coerceAtMost(valueBits, maxBits)
        let result = bitsToFloat(resultBits)
        #expect(abs(result - 5.5) <= 1e-6)

        let aboveBits = floatToBits(15.5)
        let clampedBits = kk_float_coerceAtMost(aboveBits, maxBits)
        let clamped = bitsToFloat(clampedBits)
        #expect(abs(clamped - 10.0) <= 1e-6)
    }

    // MARK: - Unsigned Coercion Runtime Tests

    @Test
    func testUnsignedCoerceRuntimeBehavior() {
        // UByte and UShort values stay in the non-negative Int range, but we
        // still compare them through the same unsigned clamping helpers.
        #expect(kk_ubyte_coerceIn(5, 1, 10) == 5)
        #expect(kk_ubyte_coerceIn(0, 1, 10) == 1)
        #expect(kk_ubyte_coerceIn(15, 1, 10) == 10)
        #expect(kk_ubyte_coerceAtLeast(5, 10) == 10)
        #expect(kk_ubyte_coerceAtMost(15, 10) == 10)

        #expect(kk_ushort_coerceIn(500, 100, 900) == 500)
        #expect(kk_ushort_coerceIn(50, 100, 900) == 100)
        #expect(kk_ushort_coerceIn(1000, 100, 900) == 900)
        #expect(kk_ushort_coerceAtLeast(50, 100) == 100)
        #expect(kk_ushort_coerceAtMost(1000, 900) == 900)

        // UInt / ULong values can cross Int.max, so verify raw bit-pattern
        // comparisons instead of signed Int ordering.
        let lower = UInt(Int.max) + 10
        let upper = lower + 20
        let middle = lower + 7
        let below = lower &- 1
        let above = upper &+ 1

        let lowerBits = unsignedToBits(lower)
        let upperBits = unsignedToBits(upper)
        let middleBits = unsignedToBits(middle)
        let belowBits = unsignedToBits(below)
        let aboveBits = unsignedToBits(above)

        #expect(bitsToUnsigned(kk_uint_coerceIn(middleBits, lowerBits, upperBits)) == middle)
        #expect(bitsToUnsigned(kk_uint_coerceIn(belowBits, lowerBits, upperBits)) == lower)
        #expect(bitsToUnsigned(kk_uint_coerceIn(aboveBits, lowerBits, upperBits)) == upper)
        #expect(bitsToUnsigned(kk_uint_coerceAtLeast(belowBits, lowerBits)) == lower)
        #expect(bitsToUnsigned(kk_uint_coerceAtMost(aboveBits, upperBits)) == upper)

        #expect(bitsToUnsigned(kk_ulong_coerceIn(middleBits, lowerBits, upperBits)) == middle)
        #expect(bitsToUnsigned(kk_ulong_coerceIn(belowBits, lowerBits, upperBits)) == lower)
        #expect(bitsToUnsigned(kk_ulong_coerceIn(aboveBits, lowerBits, upperBits)) == upper)
        #expect(bitsToUnsigned(kk_ulong_coerceAtLeast(belowBits, lowerBits)) == lower)
        #expect(bitsToUnsigned(kk_ulong_coerceAtMost(aboveBits, upperBits)) == upper)
    }

    // MARK: - Boundary Value Tests

    @Test
    func testIntBoundaryValues() {
        let int32Max = Int(Int32.max)
        let int32Min = Int(Int32.min)

        #expect(kk_int_coerceIn(int32Max, int32Max - 100, int32Max) == int32Max)
        #expect(kk_int_coerceIn(int32Min, int32Min, int32Min + 100) == int32Min)

        #expect(kk_int_coerceIn(0, Int.min, Int.max) == 0)
        #expect(kk_int_coerceIn(Int.min, Int.min, Int.max) == Int.min)
        #expect(kk_int_coerceIn(Int.max, Int.min, Int.max) == Int.max)
    }

    @Test
    func testDoubleSpecialValues() {
        let nanBits = doubleToBits(Double.nan)
        let minBits = doubleToBits(0.0)
        let maxBits = doubleToBits(1.0)

        let nanResultBits = kk_double_coerceIn(nanBits, minBits, maxBits)
        let nanResult = bitsToDouble(nanResultBits)
        #expect(nanResult.isNaN)

        let posInfBits = doubleToBits(Double.infinity)
        let negInfBits = doubleToBits(-Double.infinity)

        let posInfResultBits = kk_double_coerceIn(posInfBits, minBits, maxBits)
        let posInfResult = bitsToDouble(posInfResultBits)
        #expect(abs(posInfResult - 1.0) <= 1e-10)

        let negInfResultBits = kk_double_coerceIn(negInfBits, minBits, maxBits)
        let negInfResult = bitsToDouble(negInfResultBits)
        #expect(abs(negInfResult - 0.0) <= 1e-10)
    }

    @Test
    func testFloatSpecialValues() {
        let nanBits = floatToBits(Float.nan)
        let minBits = floatToBits(0.0)
        let maxBits = floatToBits(1.0)

        let nanResultBits = kk_float_coerceIn(nanBits, minBits, maxBits)
        let nanResult = bitsToFloat(nanResultBits)
        #expect(nanResult.isNaN)

        let posInfBits = floatToBits(Float.infinity)
        let negInfBits = floatToBits(-Float.infinity)

        let posInfResultBits = kk_float_coerceIn(posInfBits, minBits, maxBits)
        let posInfResult = bitsToFloat(posInfResultBits)
        #expect(abs(posInfResult - 1.0) <= 1e-6)

        let negInfResultBits = kk_float_coerceIn(negInfBits, minBits, maxBits)
        let negInfResult = bitsToFloat(negInfResultBits)
        #expect(abs(negInfResult - 0.0) <= 1e-6)
    }

    // MARK: - Precision Tests

    @Test
    func testFloatToDoublePrecision() {
        let preciseDouble = 1.23456789012345
        let doubleBits = doubleToBits(preciseDouble)
        let floatBits = kk_double_to_float(doubleBits)
        let convertedBackBits = kk_float_to_double_bits(floatBits)
        let convertedBack = bitsToDouble(convertedBackBits)

        #expect(abs(convertedBack - preciseDouble) > 1e-15)
        #expect(abs(convertedBack - preciseDouble) <= 1e-7)
    }

    @Test
    func testTypeConversionConsistency() {
        let testDouble = 3.141592653589793
        let bits = doubleToBits(testDouble)
        let decoded = bitsToDouble(bits)
        #expect(abs(decoded - testDouble) <= 1e-15)

        let testFloat: Float = 3.1415927
        let floatBits = floatToBits(testFloat)
        let decodedFloat = bitsToFloat(floatBits)
        #expect(abs(decodedFloat - testFloat) <= 1e-7)
    }

    // MARK: - UByte and UShort Conversion Tests (STDLIB-PRIM-002)

    @Test
    func testIntToUByteConversion() {
        #expect(kk_int_to_ubyte(100) == 100)
        #expect(kk_int_to_ubyte(-5) == 251)
        #expect(kk_int_to_ubyte(300) == 44)
        #expect(kk_int_to_ubyte(0) == 0)
        #expect(kk_int_to_ubyte(255) == 255)
    }

    @Test
    func testIntToUShortConversion() {
        #expect(kk_int_to_ushort(1000) == 1000)
        #expect(kk_int_to_ushort(-5) == 65531)
        #expect(kk_int_to_ushort(70000) == 4464)
        #expect(kk_int_to_ushort(0) == 0)
        #expect(kk_int_to_ushort(65535) == 65535)
    }

    @Test
    func testLongToUByteConversion() {
        #expect(kk_long_to_ubyte(100) == 100)
        #expect(kk_long_to_ubyte(-5) == 251)
        #expect(kk_long_to_ubyte(300) == 44)
    }

    @Test
    func testLongToUShortConversion() {
        #expect(kk_long_to_ushort(1000) == 1000)
        #expect(kk_long_to_ushort(-5) == 65531)
        #expect(kk_long_to_ushort(70000) == 4464)
    }

    @Test
    func testUIntToUByteConversion() {
        #expect(kk_uint_to_ubyte(100) == 100)
        #expect(kk_uint_to_ubyte(300) == 44)
        #expect(kk_uint_to_ubyte(0) == 0)
        #expect(kk_uint_to_ubyte(255) == 255)
    }

    // MARK: - Int/UInt 32-bit Reinterpretation Regression Tests
    //
    // kk_int_to_uint / kk_long_to_uint / kk_uint_to_int / kk_ulong_to_int used
    // to be identity functions. That happened to look right whenever the
    // source payload was already a non-negative value the target type could
    // hold as-is, but it left the Int64 payload numerically unchanged for any
    // value that needed an actual bit-pattern reinterpretation, silently
    // producing a wrong (still-negative, or out-of-range) result. Found via
    // `(-1L).toUInt()` while working on HexFormat (KSP-481).

    @Test
    func testIntToUIntConversion() {
        // Negative Int must reinterpret its bit pattern as unsigned, not
        // stay negative.
        #expect(kk_int_to_uint(-1) == Int(UInt32.max))
        #expect(kk_int_to_uint(Int(Int32.min)) == Int(UInt32(Int32.max) + 1))
        #expect(kk_int_to_uint(100) == 100)
        #expect(kk_int_to_uint(0) == 0)
    }

    @Test
    func testLongToUIntConversion() {
        // Narrowing Long -> UInt keeps only the low 32 bits, then reads them
        // as unsigned.
        #expect(kk_long_to_uint(-1) == Int(UInt32.max))
        #expect(kk_long_to_uint(100) == 100)
        // 0x1_0000_0001 truncates to 0x0000_0001.
        #expect(kk_long_to_uint(4294967297) == 1)
    }

    @Test
    func testUIntToIntConversion() {
        // UInt values at or above 2^31 must reinterpret as negative Int.
        #expect(kk_uint_to_int(Int(UInt32.max)) == -1)
        #expect(kk_uint_to_int(2147483648) == Int(Int32.min))
        #expect(kk_uint_to_int(100) == 100)
    }

    @Test
    func testULongToIntConversion() {
        // Narrowing ULong -> Int keeps only the low 32 bits, then reads them
        // as signed.
        #expect(kk_ulong_to_int(Int(UInt32.max)) == -1)
        #expect(kk_ulong_to_int(100) == 100)
        // 2^32 truncates to 0.
        #expect(kk_ulong_to_int(4294967296) == 0)
    }

    @Test
    func testUIntIntRoundTripRegression() {
        // (-1L).toUInt() == 4294967295u must hold both as a value and in
        // equality — this was returning -1 (and comparing false) before the
        // fix.
        #expect(kk_long_to_uint(-1) == kk_int_to_uint(-1))
        #expect(kk_uint_to_int(kk_int_to_uint(-1)) == -1)
    }

    // MARK: - Range-based Coercion Tests (STDLIB-CONV-006)

    @Test
    func testIntCoerceInRangeRuntimeBehavior() {
        let range = registerRuntimeObject(RuntimeRangeBox(first: 1, last: 10, step: 1))

        #expect(kk_int_coerceIn_range(5, range) == 5)
        #expect(kk_int_coerceIn_range(0, range) == 1)
        #expect(kk_int_coerceIn_range(15, range) == 10)

        #expect(kk_int_coerceIn_range(1, range) == 1)
        #expect(kk_int_coerceIn_range(10, range) == 10)
    }

    @Test
    func testIntCoerceAtLeastRangeRuntimeBehavior() {
        let range = registerRuntimeObject(RuntimeRangeBox(first: 3, last: 10, step: 1))

        #expect(kk_int_coerceAtLeast_range(5, range) == 5)
        #expect(kk_int_coerceAtLeast_range(1, range) == 3)
        #expect(kk_int_coerceAtLeast_range(3, range) == 3)
    }

    @Test
    func testIntCoerceAtMostRangeRuntimeBehavior() {
        let range = registerRuntimeObject(RuntimeRangeBox(first: 1, last: 7, step: 1))

        #expect(kk_int_coerceAtMost_range(5, range) == 5)
        #expect(kk_int_coerceAtMost_range(10, range) == 7)
        #expect(kk_int_coerceAtMost_range(7, range) == 7)
    }

    @Test
    func testDoubleCoerceInRangeRuntimeBehavior() {
        let range = registerRuntimeObject(RuntimeRangeBox(first: 1, last: 10, step: 1))

        let valueBits = doubleToBits(5.5)
        let belowBits = doubleToBits(0.5)
        let aboveBits = doubleToBits(15.5)

        let resultBits = kk_double_coerceIn_range(valueBits, range)
        let result = bitsToDouble(resultBits)
        #expect(abs(result - 5.5) <= 1e-10)

        let clampedBelowBits = kk_double_coerceIn_range(belowBits, range)
        let clampedBelow = bitsToDouble(clampedBelowBits)
        #expect(abs(clampedBelow - 1.0) <= 1e-10)

        let clampedAboveBits = kk_double_coerceIn_range(aboveBits, range)
        let clampedAbove = bitsToDouble(clampedAboveBits)
        #expect(abs(clampedAbove - 10.0) <= 1e-10)
    }

    @Test
    func testFloatCoerceInRangeRuntimeBehavior() {
        let range = registerRuntimeObject(RuntimeRangeBox(first: 1, last: 10, step: 1))

        let valueBits = floatToBits(5.5)
        let belowBits = floatToBits(0.5)
        let aboveBits = floatToBits(15.5)

        let resultBits = kk_float_coerceIn_range(valueBits, range)
        let result = bitsToFloat(resultBits)
        #expect(abs(result - 5.5) <= 1e-6)

        let clampedBelowBits = kk_float_coerceIn_range(belowBits, range)
        let clampedBelow = bitsToFloat(clampedBelowBits)
        #expect(abs(clampedBelow - 1.0) <= 1e-6)

        let clampedAboveBits = kk_float_coerceIn_range(aboveBits, range)
        let clampedAbove = bitsToFloat(clampedAboveBits)
        #expect(abs(clampedAbove - 10.0) <= 1e-6)
    }

    @Test
    func testLongCoerceInRangeRuntimeBehavior() {
        let range = registerRuntimeObject(RuntimeRangeBox(first: 1000000000, last: 10000000000, step: 1))

        #expect(kk_long_coerceIn_range(5000000000, range) == 5000000000)
        #expect(kk_long_coerceIn_range(500000000, range) == 1000000000)
        #expect(kk_long_coerceIn_range(15000000000, range) == 10000000000)
    }

    @Test
    func testRangeCoercionConsistency() {
        let range = registerRuntimeObject(RuntimeRangeBox(first: 2, last: 8, step: 1))

        let testValues = [1, 3, 5, 10]
        for value in testValues {
            let rangeResult = kk_int_coerceIn_range(value, range)
            let minMaxResult = kk_int_coerceIn(value, 2, 8)
            #expect(rangeResult == minMaxResult, "Range-based coercion should match min/max coercion for value \(value)")

            let rangeAtLeastResult = kk_int_coerceAtLeast_range(value, range)
            let minAtLeastResult = kk_int_coerceAtLeast(value, 2)
            #expect(rangeAtLeastResult == minAtLeastResult, "Range-based coerceAtLeast should match min coercion for value \(value)")

            let rangeAtMostResult = kk_int_coerceAtMost_range(value, range)
            let maxAtMostResult = kk_int_coerceAtMost(value, 8)
            #expect(rangeAtMostResult == maxAtMostResult, "Range-based coerceAtMost should match max coercion for value \(value)")
        }
    }

    @Test
    func testUIntToUShortConversion() {
        #expect(kk_uint_to_ushort(1000) == 1000)
        #expect(kk_uint_to_ushort(70000) == 4464)
        #expect(kk_uint_to_ushort(0) == 0)
        #expect(kk_uint_to_ushort(65535) == 65535)
    }

    @Test
    func testUByteToIntConversion() {
        #expect(kk_ubyte_to_int(100) == 100)
        #expect(kk_ubyte_to_int(0) == 0)
        #expect(kk_ubyte_to_int(255) == 255)
    }

    @Test
    func testUShortToIntConversion() {
        #expect(kk_ushort_to_int(1000) == 1000)
        #expect(kk_ushort_to_int(0) == 0)
        #expect(kk_ushort_to_int(65535) == 65535)
    }

    @Test
    func testUByteToLongConversion() {
        #expect(kk_ubyte_to_long(100) == 100)
        #expect(kk_ubyte_to_long(0) == 0)
        #expect(kk_ubyte_to_long(255) == 255)
    }

    @Test
    func testUShortToLongConversion() {
        #expect(kk_ushort_to_long(1000) == 1000)
        #expect(kk_ushort_to_long(0) == 0)
        #expect(kk_ushort_to_long(65535) == 65535)
    }

    // MARK: - Char Conversion Tests (STDLIB-PRIM-002)

    @Test
    func testIntToCharConversion() {
        #expect(kk_int_to_char(65) == 65)
        #expect(kk_int_to_char(0x1F600) == 0xF600)
        #expect(kk_int_to_char(-5) == 0xFFFB)
        #expect(kk_int_to_char(0x110000) == 0)
        #expect(kk_int_to_char(0) == 0)
        #expect(kk_int_to_char(0x10FFFF) == 0xFFFF)
    }

    @Test
    func testLongToCharConversion() {
        #expect(kk_long_to_char(65) == 65)
        #expect(kk_long_to_char(0x1F600) == 0xF600)
        #expect(kk_long_to_char(-5) == 0xFFFB)
        #expect(kk_long_to_char(0x110000) == 0)
    }

    @Test
    func testUIntToCharConversion() {
        #expect(kk_uint_to_char(65) == 65)
        #expect(kk_uint_to_char(0x1F600) == 0xF600)
        #expect(kk_uint_to_char(0x110000) == 0)
    }

    @Test
    func testULongToCharConversion() {
        #expect(kk_ulong_to_char(65) == 65)
        #expect(kk_ulong_to_char(0x1F600) == 0xF600)
        #expect(kk_ulong_to_char(0x110000) == 0)
    }

    @Test
    func testUByteToCharConversion() {
        #expect(kk_ubyte_to_char(65) == 65)
        #expect(kk_ubyte_to_char(255) == 255)
    }

    @Test
    func testUShortToCharConversion() {
        #expect(kk_ushort_to_char(65) == 65)
        #expect(kk_ushort_to_char(0x1F600) == 0x1F600)
        #expect(kk_ushort_to_char(65535) == 65535)
    }

    @Test
    func testCharToIntConversion() {
        #expect(kk_char_to_int(65) == 65)
        #expect(kk_char_to_int(0x1F600) == 0x1F600)
        #expect(kk_char_to_int(0) == 0)
    }

    @Test
    func testCharToLongConversion() {
        #expect(kk_char_to_long(65) == 65)
        #expect(kk_char_to_long(0x1F600) == 0x1F600)
    }

    @Test
    func testCharToUIntConversion() {
        #expect(kk_char_to_uint(65) == 65)
        #expect(kk_char_to_uint(0x1F600) == 0x1F600)
    }

    @Test
    func testCharToULongConversion() {
        #expect(kk_char_to_ulong(65) == 65)
        #expect(kk_char_to_ulong(0x1F600) == 0x1F600)
    }

    // MARK: - Additional Conversion Tests (STDLIB-PRIM-002)

    @Test
    func testFloatToUIntConversion() {
        #expect(kk_float_to_uint(kk_float_to_bits(Float(3.14))) == 3)
        #expect(kk_float_to_uint(kk_float_to_bits(Float(-1.5))) == 0)
        #expect(kk_float_to_uint(kk_float_to_bits(Float.nan)) == 0)
        #expect(kk_float_to_uint(kk_float_to_bits(Float(UInt32.max))) == Int(UInt32.max))
    }

    @Test
    func testDoubleToUIntConversion() {
        #expect(kk_double_to_uint(kk_double_to_bits(3.14)) == 3)
        #expect(kk_double_to_uint(kk_double_to_bits(-1.5)) == 0)
        #expect(kk_double_to_uint(kk_double_to_bits(Double.nan)) == 0)
        #expect(kk_double_to_uint(kk_double_to_bits(Double(UInt32.max))) == Int(UInt32.max))
    }

    @Test
    func testFloatToULongConversion() {
        #expect(kk_float_to_ulong(kk_float_to_bits(Float(3.14))) == 3)
        #expect(kk_float_to_ulong(kk_float_to_bits(Float(-1.5))) == 0)
        #expect(kk_float_to_ulong(kk_float_to_bits(Float.nan)) == 0)
    }

    @Test
    func testDoubleToULongConversion() {
        #expect(kk_double_to_ulong(kk_double_to_bits(3.14)) == 3)
        #expect(kk_double_to_ulong(kk_double_to_bits(-1.5)) == 0)
        #expect(kk_double_to_ulong(kk_double_to_bits(Double.nan)) == 0)
    }

    @Test
    func testByteToUIntConversion() {
        #expect(kk_byte_to_uint(100) == 100)
        #expect(kk_byte_to_uint(-5) == 251)
    }

    @Test
    func testShortToUIntConversion() {
        #expect(kk_short_to_uint(1000) == 1000)
        #expect(kk_short_to_uint(-5) == 65531)
    }

    @Test
    func testByteToULongConversion() {
        #expect(kk_byte_to_ulong(100) == 100)
        #expect(kk_byte_to_ulong(-5) == 251)
    }

    @Test
    func testShortToULongConversion() {
        #expect(kk_short_to_ulong(1000) == 1000)
        #expect(kk_short_to_ulong(-5) == 65531)
    }

    @Test
    func testByteToCharConversion() {
        #expect(kk_byte_to_char(65) == 65)
        #expect(kk_byte_to_char(-5) == 0xFFFB)
    }

    @Test
    func testShortToCharConversion() {
        #expect(kk_short_to_char(65) == 65)
        #expect(kk_short_to_char(0x1F600) == 0xF600)
    }

    @Test
    func testFloatToCharConversion() {
        #expect(kk_float_to_char(kk_float_to_bits(Float(65.0))) == 65)
        #expect(kk_float_to_char(kk_float_to_bits(Float.nan)) == 0)
        #expect(kk_float_to_char(kk_float_to_bits(Float(-1.0))) == 0)
    }

    @Test
    func testDoubleToCharConversion() {
        #expect(kk_double_to_char(kk_double_to_bits(65.0)) == 65)
        #expect(kk_double_to_char(kk_double_to_bits(Double.nan)) == 0)
        #expect(kk_double_to_char(kk_double_to_bits(-1.0)) == 0)
    }

    // MARK: - Cross-Type Conversion Tests

    @Test
    func testCrossTypeUByteConversions() {
        let original = 200
        let asUByte = kk_int_to_ubyte(original)
        let backToInt = kk_ubyte_to_int(asUByte)
        let asLong = kk_ubyte_to_long(asUByte)
        let asUInt = kk_ubyte_to_uint(asUByte)
        let asULong = kk_ubyte_to_ulong(asUByte)
        let asChar = kk_ubyte_to_char(asUByte)

        #expect(backToInt == original)
        #expect(asLong == original)
        #expect(asUInt == original)
        #expect(asULong == original)
        #expect(asChar == original)
    }

    @Test
    func testCrossTypeUShortConversions() {
        let original = 50000
        let asUShort = kk_int_to_ushort(original)
        let backToInt = kk_ushort_to_int(asUShort)
        let asLong = kk_ushort_to_long(asUShort)
        let asUInt = kk_ushort_to_uint(asUShort)
        let asULong = kk_ushort_to_ulong(asUShort)
        let asChar = kk_ushort_to_char(asUShort)

        #expect(backToInt == original)
        #expect(asLong == original)
        #expect(asUInt == original)
        #expect(asULong == original)
        #expect(asChar == original)
    }

    @Test
    func testCrossTypeCharConversions() {
        let original = 0x1F600 // 😀 emoji
        let asChar = kk_int_to_char(original)
        let backToInt = kk_char_to_int(asChar)
        let asLong = kk_char_to_long(asChar)
        let asUInt = kk_char_to_uint(asChar)
        let asULong = kk_char_to_ulong(asChar)

        #expect(backToInt == 0xF600)
        #expect(asLong == 0xF600)
        #expect(asUInt == 0xF600)
        #expect(asULong == 0xF600)
    }

}
#endif
