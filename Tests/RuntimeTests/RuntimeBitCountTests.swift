#if canImport(Testing)
import Testing
@testable import Runtime

/// Edge case tests for the kk_int_countOneBits, kk_int_countLeadingZeroBits,
/// kk_int_countTrailingZeroBits runtime functions (STDLIB-604, STDLIB-605, STDLIB-606).
///
/// These implement Kotlin `Int.countOneBits`, `Int.countLeadingZeroBits`, and
/// `Int.countTrailingZeroBits` with Kotlin Int (32-bit signed) semantics:
/// the Swift Int argument is truncated to Int32 before querying bit properties.
@Suite
struct RuntimeBitCountTests {

    // MARK: - Shared constants

    /// 0xAAAAAAAA as a signed Int, converted via two's complement.
    private static let alternating0xAAAAAAAA = Int(Int32(bitPattern: 0xAAAA_AAAA))

    // MARK: - countOneBits (STDLIB-604)

    @Test
    func testCountOneBits_zero() {
        #expect(kk_int_countOneBits(0) == 0)
    }

    @Test
    func testCountOneBits_one() {
        #expect(kk_int_countOneBits(1) == 1)
    }

    @Test
    func testCountOneBits_minusOne() {
        // Kotlin: (-1).countOneBits() == 32 (all 32 bits set)
        #expect(kk_int_countOneBits(-1) == 32)
    }

    @Test
    func testCountOneBits_int32Max() {
        // Int32.max == 0x7FFF_FFFF -> 31 bits set
        #expect(kk_int_countOneBits(Int(Int32.max)) == 31)
    }

    @Test
    func testCountOneBits_int32Min() {
        // Int32.min == 0x8000_0000 -> 1 bit set (sign bit)
        #expect(kk_int_countOneBits(Int(Int32.min)) == 1)
    }

    @Test
    func testCountOneBits_powersOfTwo() {
        // Each power of two has exactly 1 bit set
        for shift in 0..<31 {
            let value = 1 << shift
            #expect(
                kk_int_countOneBits(value) == 1,
                "Expected 1 bit set for 1 << \(shift)"
            )
        }
    }

    @Test
    func testCountOneBits_alternatingPattern_0x55555555() {
        // 0x55555555 = 0101...0101 -> 16 bits set
        #expect(kk_int_countOneBits(0x5555_5555) == 16)
    }

    @Test
    func testCountOneBits_alternatingPattern_0xAAAAAAAA() {
        // 0xAAAAAAAA = 1010...1010 -> 16 bits set
        #expect(kk_int_countOneBits(Self.alternating0xAAAAAAAA) == 16)
    }

    @Test
    func testCountOneBits_byteBoundaryValues() {
        // 0x000000FF -> 8 bits set (low byte full)
        #expect(kk_int_countOneBits(0xFF) == 8)
        // 0x0000FF00 -> 8 bits set (second byte full)
        #expect(kk_int_countOneBits(0xFF00) == 8)
        // 0x00FF0000 -> 8 bits set (third byte full)
        #expect(kk_int_countOneBits(0x00FF_0000) == 8)
        // 0xFFFF -> 16 bits set (low two bytes)
        #expect(kk_int_countOneBits(0xFFFF) == 16)
        // 0x00FFFFFF -> 24 bits set (low three bytes)
        #expect(kk_int_countOneBits(0x00FF_FFFF) == 24)
    }

    @Test
    func testCountOneBits_sparsePattern() {
        // 0x01010101 -> 4 bits set (one per byte)
        #expect(kk_int_countOneBits(0x0101_0101) == 4)
        // 0x10000001 -> 2 bits set
        #expect(kk_int_countOneBits(0x1000_0001) == 2)
    }

    @Test
    func testCountOneBits_densePattern() {
        // 0xFFFFFFFE -> 31 bits set (all except LSB)
        #expect(kk_int_countOneBits(Int(Int32(bitPattern: 0xFFFF_FFFE))) == 31)
        // 0x7FFFFFFE -> 30 bits set (all except MSB and LSB)
        #expect(kk_int_countOneBits(0x7FFF_FFFE) == 30)
    }

    @Test
    func testCountOneBits_smallNegativeValues() {
        // -2 == 0xFFFFFFFE -> 31 bits set
        #expect(kk_int_countOneBits(-2) == 31)
        // -3 == 0xFFFFFFFD -> 31 bits set
        #expect(kk_int_countOneBits(-3) == 31)
        // -128 == 0xFFFFFF80 -> 25 bits set
        #expect(kk_int_countOneBits(-128) == 25)
        // -256 == 0xFFFFFF00 -> 24 bits set
        #expect(kk_int_countOneBits(-256) == 24)
    }

    @Test
    func testCountOneBits_64bitTruncation() {
        // When a 64-bit value has upper 32 bits set but lower 32 bits are zero,
        // the runtime must truncate to Int32 and see only zeros.
        // 0x1_0000_0000 truncated to Int32 -> 0x0000_0000 -> 0 bits
        let valueAbove32Bit = Int(bitPattern: 0x1_0000_0000)
        #expect(kk_int_countOneBits(valueAbove32Bit) == 0)

        // 0xFFFF_FFFF_0000_0000 truncated to Int32 -> 0x0000_0000 -> 0 bits
        let highBitsOnly = Int(bitPattern: 0xFFFF_FFFF_0000_0000)
        #expect(kk_int_countOneBits(highBitsOnly) == 0)

        // 0x1_0000_0001 truncated to Int32 -> 0x0000_0001 -> 1 bit
        let highAndLow = Int(bitPattern: 0x1_0000_0001)
        #expect(kk_int_countOneBits(highAndLow) == 1)

        // 0xFFFF_FFFF_FFFF_FFFF truncated to Int32 -> 0xFFFF_FFFF -> 32 bits
        #expect(kk_int_countOneBits(-1) == 32)
    }

    // MARK: - countLeadingZeroBits (STDLIB-605)

    @Test
    func testCountLeadingZeroBits_zero() {
        // All 32 bits are zero
        #expect(kk_int_countLeadingZeroBits(0) == 32)
    }

    @Test
    func testCountLeadingZeroBits_one() {
        // 0x00000001 -> 31 leading zeros
        #expect(kk_int_countLeadingZeroBits(1) == 31)
    }

    @Test
    func testCountLeadingZeroBits_minusOne() {
        // 0xFFFFFFFF -> MSB is set, 0 leading zeros
        #expect(kk_int_countLeadingZeroBits(-1) == 0)
    }

    @Test
    func testCountLeadingZeroBits_int32Max() {
        // 0x7FFFFFFF -> MSB is 0, 1 leading zero
        #expect(kk_int_countLeadingZeroBits(Int(Int32.max)) == 1)
    }

    @Test
    func testCountLeadingZeroBits_int32Min() {
        // 0x80000000 -> MSB is set, 0 leading zeros
        #expect(kk_int_countLeadingZeroBits(Int(Int32.min)) == 0)
    }

    @Test
    func testCountLeadingZeroBits_powersOfTwo() {
        // 1 << n has (31 - n) leading zeros
        for shift in 0..<31 {
            let value = 1 << shift
            #expect(
                kk_int_countLeadingZeroBits(value) == 31 - shift,
                "Expected \(31 - shift) leading zeros for 1 << \(shift)"
            )
        }
    }

    @Test
    func testCountLeadingZeroBits_alternatingPattern_0x55555555() {
        // 0x55555555 -> MSB (bit 31) is 0, bit 30 is 1 -> 1 leading zero
        #expect(kk_int_countLeadingZeroBits(0x5555_5555) == 1)
    }

    @Test
    func testCountLeadingZeroBits_alternatingPattern_0xAAAAAAAA() {
        // 0xAAAAAAAA -> MSB is set -> 0 leading zeros
        #expect(kk_int_countLeadingZeroBits(Self.alternating0xAAAAAAAA) == 0)
    }

    @Test
    func testCountLeadingZeroBits_byteBoundaryValues() {
        // 0x000000FF -> highest set bit is bit 7 -> 24 leading zeros
        #expect(kk_int_countLeadingZeroBits(0xFF) == 24)
        // 0x0000FF00 -> highest set bit is bit 15 -> 16 leading zeros
        #expect(kk_int_countLeadingZeroBits(0xFF00) == 16)
        // 0x00FF0000 -> highest set bit is bit 23 -> 8 leading zeros
        #expect(kk_int_countLeadingZeroBits(0x00FF_0000) == 8)
        // 0x0000FFFF -> highest set bit is bit 15 -> 16 leading zeros
        #expect(kk_int_countLeadingZeroBits(0xFFFF) == 16)
    }

    @Test
    func testCountLeadingZeroBits_smallValues() {
        // 2 == 0b10 -> bit 1 is highest -> 30 leading zeros
        #expect(kk_int_countLeadingZeroBits(2) == 30)
        // 3 == 0b11 -> bit 1 is highest -> 30 leading zeros
        #expect(kk_int_countLeadingZeroBits(3) == 30)
        // 7 == 0b111 -> bit 2 is highest -> 29 leading zeros
        #expect(kk_int_countLeadingZeroBits(7) == 29)
        // 255 == 0xFF -> bit 7 is highest -> 24 leading zeros
        #expect(kk_int_countLeadingZeroBits(255) == 24)
    }

    @Test
    func testCountLeadingZeroBits_negativeValues() {
        // All negative Int32 values have MSB set -> 0 leading zeros
        #expect(kk_int_countLeadingZeroBits(-2) == 0)
        #expect(kk_int_countLeadingZeroBits(-128) == 0)
        #expect(kk_int_countLeadingZeroBits(-256) == 0)
        #expect(kk_int_countLeadingZeroBits(-65536) == 0)
    }

    @Test
    func testCountLeadingZeroBits_64bitTruncation() {
        // 0x1_0000_0000 truncated to Int32 -> 0 -> 32 leading zeros
        let valueAbove32Bit = Int(bitPattern: 0x1_0000_0000)
        #expect(kk_int_countLeadingZeroBits(valueAbove32Bit) == 32)

        // 0x8000_0000_0000_0001 truncated to Int32 -> 0x0000_0001 -> 31 leading zeros
        let highBitAndOne = Int(bitPattern: 0x8000_0000_0000_0001)
        #expect(kk_int_countLeadingZeroBits(highBitAndOne) == 31)
    }

    // MARK: - countTrailingZeroBits (STDLIB-606)

    @Test
    func testCountTrailingZeroBits_zero() {
        // All 32 bits are zero -> 32 trailing zeros
        #expect(kk_int_countTrailingZeroBits(0) == 32)
    }

    @Test
    func testCountTrailingZeroBits_one() {
        // 0x00000001 -> LSB is set, 0 trailing zeros
        #expect(kk_int_countTrailingZeroBits(1) == 0)
    }

    @Test
    func testCountTrailingZeroBits_minusOne() {
        // 0xFFFFFFFF -> LSB is set, 0 trailing zeros
        #expect(kk_int_countTrailingZeroBits(-1) == 0)
    }

    @Test
    func testCountTrailingZeroBits_int32Max() {
        // 0x7FFFFFFF -> LSB is set, 0 trailing zeros
        #expect(kk_int_countTrailingZeroBits(Int(Int32.max)) == 0)
    }

    @Test
    func testCountTrailingZeroBits_int32Min() {
        // 0x80000000 -> only MSB set, 31 trailing zeros
        #expect(kk_int_countTrailingZeroBits(Int(Int32.min)) == 31)
    }

    @Test
    func testCountTrailingZeroBits_powersOfTwo() {
        // 1 << n has exactly n trailing zeros
        for shift in 0..<31 {
            let value = 1 << shift
            #expect(
                kk_int_countTrailingZeroBits(value) == shift,
                "Expected \(shift) trailing zeros for 1 << \(shift)"
            )
        }
    }

    @Test
    func testCountTrailingZeroBits_alternatingPattern_0x55555555() {
        // 0x55555555 -> LSB is set -> 0 trailing zeros
        #expect(kk_int_countTrailingZeroBits(0x5555_5555) == 0)
    }

    @Test
    func testCountTrailingZeroBits_alternatingPattern_0xAAAAAAAA() {
        // 0xAAAAAAAA -> LSB is 0, bit 1 is set -> 1 trailing zero
        #expect(kk_int_countTrailingZeroBits(Self.alternating0xAAAAAAAA) == 1)
    }

    @Test
    func testCountTrailingZeroBits_byteBoundaryValues() {
        // 0x00000100 -> bit 8 is lowest set -> 8 trailing zeros
        #expect(kk_int_countTrailingZeroBits(0x100) == 8)
        // 0x00010000 -> bit 16 is lowest set -> 16 trailing zeros
        #expect(kk_int_countTrailingZeroBits(0x0001_0000) == 16)
        // 0x01000000 -> bit 24 is lowest set -> 24 trailing zeros
        #expect(kk_int_countTrailingZeroBits(0x0100_0000) == 24)
        // 0xFF00 -> bit 8 is lowest set -> 8 trailing zeros
        #expect(kk_int_countTrailingZeroBits(0xFF00) == 8)
    }

    @Test
    func testCountTrailingZeroBits_evenNumbers() {
        // 2 == 0b10 -> 1 trailing zero
        #expect(kk_int_countTrailingZeroBits(2) == 1)
        // 4 == 0b100 -> 2 trailing zeros
        #expect(kk_int_countTrailingZeroBits(4) == 2)
        // 6 == 0b110 -> 1 trailing zero
        #expect(kk_int_countTrailingZeroBits(6) == 1)
        // 12 == 0b1100 -> 2 trailing zeros
        #expect(kk_int_countTrailingZeroBits(12) == 2)
    }

    @Test
    func testCountTrailingZeroBits_negativeValues() {
        // -2 == 0xFFFFFFFE -> LSB is 0, bit 1 is set -> 1 trailing zero
        #expect(kk_int_countTrailingZeroBits(-2) == 1)
        // -4 == 0xFFFFFFFC -> bits 0,1 are 0 -> 2 trailing zeros
        #expect(kk_int_countTrailingZeroBits(-4) == 2)
        // -128 == 0xFFFFFF80 -> bits 0-6 are 0 -> 7 trailing zeros
        #expect(kk_int_countTrailingZeroBits(-128) == 7)
        // -256 == 0xFFFFFF00 -> bits 0-7 are 0 -> 8 trailing zeros
        #expect(kk_int_countTrailingZeroBits(-256) == 8)
    }

    @Test
    func testCountTrailingZeroBits_64bitTruncation() {
        // 0x1_0000_0000 truncated to Int32 -> 0 -> 32 trailing zeros
        let valueAbove32Bit = Int(bitPattern: 0x1_0000_0000)
        #expect(kk_int_countTrailingZeroBits(valueAbove32Bit) == 32)

        // 0xFFFF_FFFF_0000_0100 truncated to Int32 -> 0x0000_0100 -> 8 trailing zeros
        let highMaskWithLow = Int(bitPattern: 0xFFFF_FFFF_0000_0100)
        #expect(kk_int_countTrailingZeroBits(highMaskWithLow) == 8)
    }

    // MARK: - Cross-function invariants (STDLIB-501)

    @Test
    func testBitCountInvariant_oneBitsPlusZeroBitsEquals32() {
        // For any 32-bit value:
        // countLeadingZeroBits + countTrailingZeroBits + countOneBits <= 32
        // (equals 32 only when ones form a single contiguous block)
        // When ones are non-contiguous, the internal zero gaps are not counted
        // by either leading or trailing, so the sum is strictly less than 32.
        let testValues: [Int] = [
            0, 1, -1, 42, 255, 256, 1024,
            0x7FFF_FFFF, Int(Int32.min), -2, -128,
            0x5555_5555, Self.alternating0xAAAAAAAA,
            0x0101_0101, 0x00FF_00FF,
        ]
        for value in testValues {
            let ones = kk_int_countOneBits(value)
            let leading = kk_int_countLeadingZeroBits(value)
            let trailing = kk_int_countTrailingZeroBits(value)
            if value == 0 {
                #expect(leading == 32)
                #expect(trailing == 32)
                #expect(ones == 0)
                continue
            }
            // The sum of leading zeros, trailing zeros, and one-bits
            // must be <= 32 (equals 32 only when ones form a contiguous block)
            #expect(
                leading + trailing + ones <= 32,
                "Invariant violated for value \(value): leading=\(leading) trailing=\(trailing) ones=\(ones)"
            )
        }
    }

    @Test
    func testBitCountInvariant_zeroHas32LeadingAndTrailingZeros() {
        // Zero is special: all 32 bits are zero in both directions
        #expect(kk_int_countLeadingZeroBits(0) == 32)
        #expect(kk_int_countTrailingZeroBits(0) == 32)
        #expect(kk_int_countOneBits(0) == 0)
    }

    @Test
    func testBitCountInvariant_contiguousOneBitsSum32() {
        // Values with a single contiguous run of 1-bits:
        // leading + trailing + ones == 32 exactly
        // 0x00FF0000 = 8 leading + 16 trailing + 8 ones = 32
        #expect(
            kk_int_countLeadingZeroBits(0x00FF_0000)
            + kk_int_countTrailingZeroBits(0x00FF_0000)
            + kk_int_countOneBits(0x00FF_0000) == 32
        )
        // 0x0000FFFF = 16 leading + 0 trailing + 16 ones = 32
        #expect(
            kk_int_countLeadingZeroBits(0xFFFF)
            + kk_int_countTrailingZeroBits(0xFFFF)
            + kk_int_countOneBits(0xFFFF) == 32
        )
    }

    @Test
    func testBitCountInvariant_powerOfTwoIdentity() {
        // For a power of two 1 << n:
        //   oneBits == 1, leadingZeros == 31 - n, trailingZeros == n
        for n in 0..<31 {
            let value = 1 << n
            #expect(kk_int_countOneBits(value) == 1)
            #expect(kk_int_countLeadingZeroBits(value) == 31 - n)
            #expect(kk_int_countTrailingZeroBits(value) == n)
        }
    }

}
#endif
