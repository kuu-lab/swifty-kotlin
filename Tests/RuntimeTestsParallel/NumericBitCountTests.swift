#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct NumericBitCountTests {
    private func isPowerOfTwo32(_ value: Int) -> Bool {
        let bits = UInt32(bitPattern: Int32(truncatingIfNeeded: value))
        return bits != 0 && (bits & (bits &- 1)) == 0
    }

    private func isPowerOfTwo64(_ value: Int) -> Bool {
        let bits = UInt(bitPattern: value)
        return bits != 0 && (bits & (bits &- 1)) == 0
    }

    // MARK: - Int Bit Count Tests (32-bit semantics)

    @Test
    func testIntCountOneBitsBasicValues() {
        #expect(kk_int_countOneBits(0) == 0)
        #expect(kk_int_countOneBits(1) == 1)
        #expect(kk_int_countOneBits(2) == 1)
        #expect(kk_int_countOneBits(3) == 2)
        #expect(kk_int_countOneBits(0xFFFFFFFF) == 32)
    }

    @Test
    func testIntCountOneBitsNegativeValues() {
        #expect(kk_int_countOneBits(-1) == 32)
        #expect(kk_int_countOneBits(-2) == 31)
        #expect(kk_int_countOneBits(Int(Int32.min)) == 1)
    }

    @Test
    func testIntCountLeadingZeroBitsBasicValues() {
        #expect(kk_int_countLeadingZeroBits(0) == 32)
        #expect(kk_int_countLeadingZeroBits(1) == 31)
        #expect(kk_int_countLeadingZeroBits(0x80000000) == 0)
        #expect(kk_int_countLeadingZeroBits(0x7FFFFFFF) == 1)
    }

    @Test
    func testIntCountLeadingZeroBitsNegativeValues() {
        #expect(kk_int_countLeadingZeroBits(-1) == 0)
        #expect(kk_int_countLeadingZeroBits(Int(Int32.min)) == 0)
    }

    @Test
    func testIntCountTrailingZeroBitsBasicValues() {
        #expect(kk_int_countTrailingZeroBits(0) == 32)
        #expect(kk_int_countTrailingZeroBits(1) == 0)
        #expect(kk_int_countTrailingZeroBits(2) == 1)
        #expect(kk_int_countTrailingZeroBits(4) == 2)
        #expect(kk_int_countTrailingZeroBits(0x80000000) == 31)
    }

    @Test
    func testIntCountTrailingZeroBitsNegativeValues() {
        #expect(kk_int_countTrailingZeroBits(-1) == 0)
        #expect(kk_int_countTrailingZeroBits(-2) == 1)
        #expect(kk_int_countTrailingZeroBits(Int(Int32.min)) == 31)
    }

    // MARK: - Edge Case Tests

    @Test
    func testBitCountPowerOfTwoValues() {
        for i in 0..<31 {
            let powerOfTwo = 1 << i
            #expect(kk_int_countOneBits(powerOfTwo) == 1, "2^\(i)")
            #expect(kk_int_countTrailingZeroBits(powerOfTwo) == i, "2^\(i)")
            #expect(kk_int_countLeadingZeroBits(powerOfTwo) == 31 - i, "2^\(i)")
        }
    }

    @Test
    func testBitCountComplementaryValues() {
        for i in 0..<16 {
            let value = 1 << i
            let complement = ~value & 0xFFFFFFFF

            let onesInValue = kk_int_countOneBits(value)
            let onesInComplement = kk_int_countOneBits(complement)

            #expect(onesInValue + onesInComplement == 32)
        }
    }

    // MARK: - Regression Tests

    @Test
    func testBitCountRegressionForKnownValues() {
        let knownValues: [(value: Int, expectedOnes: Int, expectedLeadingZeros: Int, expectedTrailingZeros: Int)] = [
            (0, 0, 32, 32),
            (1, 1, 31, 0),
            (-1, 32, 0, 0),
            (0x80000000, 1, 0, 31),
            (0x7FFFFFFF, 31, 1, 0),
            (0xFFFFFFFF, 32, 0, 0),
            (Int(Int32.min), 1, 0, 31),
            (Int(Int32.max), 31, 1, 0)
        ]

        for (value, expectedOnes, expectedLeadingZeros, expectedTrailingZeros) in knownValues {
            #expect(kk_int_countOneBits(value) == expectedOnes, "value=\(value)")
            #expect(kk_int_countLeadingZeroBits(value) == expectedLeadingZeros, "value=\(value)")
            #expect(kk_int_countTrailingZeroBits(value) == expectedTrailingZeros, "value=\(value)")
        }
    }

    @Test
    func testBitCountWithBitManipulation() {
        for value in [0, 1, 2, 3, 4, 7, 8, 15, 16, 31, 32, 63, 64, 127, 128, 255, 256, 511, 512, 1023] {
            var manualOnes = 0
            var tempValue = value & 0xFFFFFFFF
            for _ in 0..<32 {
                if tempValue & 1 != 0 {
                    manualOnes += 1
                }
                tempValue >>= 1
            }

            #expect(kk_int_countOneBits(value) == manualOnes, "value=\(value)")
        }
    }

    @Test
    func testOptimizedBitManipulationCorrectness() {
        let testValues: [Int] = [
            0, 1, -1, 42, 255, 256, 1024,
            0x7FFF_FFFF, Int(Int32.min), -2, -128,
            0x5555_5555, Int(Int32(bitPattern: 0xAAAA_AAAA)),
            0x0101_0101, 0x00FF_00FF, 0x8000_0000, 0x0000_0001
        ]

        for value in testValues {
            for distance in [0, 1, 7, 15, 31] {
                let rotatedLeft = kk_int_rotateLeft(value, distance)
                let rotatedRight = kk_int_rotateRight(value, distance)

                #expect(kk_int_rotateRight(rotatedLeft, distance) & 0xFFFFFFFF == value & 0xFFFFFFFF,
                    "rotateLeft→Right value=\(value), distance=\(distance)")
                #expect(kk_int_rotateLeft(rotatedRight, distance) & 0xFFFFFFFF == value & 0xFFFFFFFF,
                    "rotateRight→Left value=\(value), distance=\(distance)")
            }

            let highest = kk_int_highestOneBit(value)
            let lowest = kk_int_lowestOneBit(value)

            if value != 0 {
                #expect(highest != 0)
                #expect(lowest != 0)
                #expect(isPowerOfTwo32(highest), "highestOneBit(\(value))")
                #expect(isPowerOfTwo32(lowest), "lowestOneBit(\(value))")
            } else {
                #expect(highest == 0)
                #expect(lowest == 0)
            }

            let takeHighest = kk_int_takeHighestOneBit(value)
            let takeLowest = kk_int_takeLowestOneBit(value)

            if value != 0 {
                #expect(takeHighest != 0)
                #expect(takeLowest != 0)
                #expect(takeHighest & highest == highest)
                #expect(takeLowest & lowest == lowest)
            } else {
                #expect(takeHighest == 0)
                #expect(takeLowest == 0)
            }
        }
    }

    @Test
    func testOptimizedLongBitManipulationCorrectness() {
        let testValues: [Int] = [
            0, 1, -1, 42, 255, 256, 1024,
            Int.max, Int.min, -2, -128,
            Int(bitPattern: 0x5555_5555_5555_5555), Int(bitPattern: 0xAAAA_AAAA_AAAA_AAAA),
            Int(bitPattern: 0x8000_0000_0000_0000), Int(bitPattern: 0x0000_0000_0000_0001)
        ]

        for value in testValues {
            for distance in [0, 1, 31, 63] {
                let rotatedLeft = kk_long_rotateLeft(value, distance)
                let rotatedRight = kk_long_rotateRight(value, distance)

                #expect(kk_long_rotateRight(rotatedLeft, distance) == value,
                    "rotateLeft→Right value=\(value), distance=\(distance)")
                #expect(kk_long_rotateLeft(rotatedRight, distance) == value,
                    "rotateRight→Left value=\(value), distance=\(distance)")
            }

            let highest = kk_long_highestOneBit(value)
            let lowest = kk_long_lowestOneBit(value)

            if value != 0 {
                #expect(highest != 0)
                #expect(lowest != 0)
                #expect(isPowerOfTwo64(highest), "highestOneBit(\(value))")
                #expect(isPowerOfTwo64(lowest), "lowestOneBit(\(value))")
            } else {
                #expect(highest == 0)
                #expect(lowest == 0)
            }
        }
    }

    @Test
    func testLowestOneBitHandlesMinimumValues() {
        #expect(kk_int_lowestOneBit(Int(Int32.min)) == Int(Int32.min))
        #expect(kk_int_takeLowestOneBit(Int(Int32.min)) == Int(Int32.min))
        #expect(kk_long_lowestOneBit(Int.min) == Int.min)
        #expect(kk_long_takeLowestOneBit(Int.min) == Int.min)
    }
}
#endif
