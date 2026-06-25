import XCTest
@testable import Runtime

final class NumericBitCountTests: XCTestCase {
    private func isPowerOfTwo32(_ value: Int) -> Bool {
        let bits = UInt32(bitPattern: Int32(truncatingIfNeeded: value))
        return bits != 0 && (bits & (bits &- 1)) == 0
    }

    private func isPowerOfTwo64(_ value: Int) -> Bool {
        let bits = UInt(bitPattern: value)
        return bits != 0 && (bits & (bits &- 1)) == 0
    }

    // MARK: - Int Bit Count Tests (32-bit semantics)

    func testIntCountOneBitsBasicValues() {
        XCTAssertEqual(kk_int_countOneBits(0), 0)
        XCTAssertEqual(kk_int_countOneBits(1), 1)
        XCTAssertEqual(kk_int_countOneBits(2), 1)
        XCTAssertEqual(kk_int_countOneBits(3), 2)
        XCTAssertEqual(kk_int_countOneBits(0xFFFFFFFF), 32)
    }

    func testIntCountOneBitsNegativeValues() {
        XCTAssertEqual(kk_int_countOneBits(-1), 32)
        XCTAssertEqual(kk_int_countOneBits(-2), 31)
        XCTAssertEqual(kk_int_countOneBits(Int(Int32.min)), 1)
    }

    func testIntCountLeadingZeroBitsBasicValues() {
        XCTAssertEqual(kk_int_countLeadingZeroBits(0), 32)
        XCTAssertEqual(kk_int_countLeadingZeroBits(1), 31)
        XCTAssertEqual(kk_int_countLeadingZeroBits(0x80000000), 0)
        XCTAssertEqual(kk_int_countLeadingZeroBits(0x7FFFFFFF), 1)
    }

    func testIntCountLeadingZeroBitsNegativeValues() {
        XCTAssertEqual(kk_int_countLeadingZeroBits(-1), 0)
        XCTAssertEqual(kk_int_countLeadingZeroBits(Int(Int32.min)), 0)
    }

    func testIntCountTrailingZeroBitsBasicValues() {
        XCTAssertEqual(kk_int_countTrailingZeroBits(0), 32)
        XCTAssertEqual(kk_int_countTrailingZeroBits(1), 0)
        XCTAssertEqual(kk_int_countTrailingZeroBits(2), 1)
        XCTAssertEqual(kk_int_countTrailingZeroBits(4), 2)
        XCTAssertEqual(kk_int_countTrailingZeroBits(0x80000000), 31)
    }

    func testIntCountTrailingZeroBitsNegativeValues() {
        XCTAssertEqual(kk_int_countTrailingZeroBits(-1), 0)
        XCTAssertEqual(kk_int_countTrailingZeroBits(-2), 1)
        XCTAssertEqual(kk_int_countTrailingZeroBits(Int(Int32.min)), 31)
    }

    // MARK: - Edge Case Tests

    func testBitCountPowerOfTwoValues() {
        for i in 0..<31 {
            let powerOfTwo = 1 << i
            XCTAssertEqual(kk_int_countOneBits(powerOfTwo), 1, "2^\(i)")
            XCTAssertEqual(kk_int_countTrailingZeroBits(powerOfTwo), i, "2^\(i)")
            XCTAssertEqual(kk_int_countLeadingZeroBits(powerOfTwo), 31 - i, "2^\(i)")
        }
    }

    func testBitCountComplementaryValues() {
        for i in 0..<16 {
            let value = 1 << i
            let complement = ~value & 0xFFFFFFFF

            let onesInValue = kk_int_countOneBits(value)
            let onesInComplement = kk_int_countOneBits(complement)

            XCTAssertEqual(onesInValue + onesInComplement, 32)
        }
    }

    // MARK: - Regression Tests

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
            XCTAssertEqual(kk_int_countOneBits(value), expectedOnes, "value=\(value)")
            XCTAssertEqual(kk_int_countLeadingZeroBits(value), expectedLeadingZeros, "value=\(value)")
            XCTAssertEqual(kk_int_countTrailingZeroBits(value), expectedTrailingZeros, "value=\(value)")
        }
    }

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

            XCTAssertEqual(kk_int_countOneBits(value), manualOnes, "value=\(value)")
        }
    }

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

                XCTAssertEqual(kk_int_rotateRight(rotatedLeft, distance) & 0xFFFFFFFF, value & 0xFFFFFFFF,
                    "rotateLeft→Right value=\(value), distance=\(distance)")
                XCTAssertEqual(kk_int_rotateLeft(rotatedRight, distance) & 0xFFFFFFFF, value & 0xFFFFFFFF,
                    "rotateRight→Left value=\(value), distance=\(distance)")
            }

            let highest = kk_int_highestOneBit(value)
            let lowest = kk_int_lowestOneBit(value)

            if value != 0 {
                XCTAssertNotEqual(highest, 0)
                XCTAssertNotEqual(lowest, 0)
                XCTAssertTrue(isPowerOfTwo32(highest), "highestOneBit(\(value))")
                XCTAssertTrue(isPowerOfTwo32(lowest), "lowestOneBit(\(value))")
            } else {
                XCTAssertEqual(highest, 0)
                XCTAssertEqual(lowest, 0)
            }

            let takeHighest = kk_int_takeHighestOneBit(value)
            let takeLowest = kk_int_takeLowestOneBit(value)

            if value != 0 {
                XCTAssertNotEqual(takeHighest, 0)
                XCTAssertNotEqual(takeLowest, 0)
                XCTAssertEqual(takeHighest & highest, highest)
                XCTAssertEqual(takeLowest & lowest, lowest)
            } else {
                XCTAssertEqual(takeHighest, 0)
                XCTAssertEqual(takeLowest, 0)
            }
        }
    }

    func testOptimizedLongBitManipulationCorrectness() {
        let testValues: [Int] = [
            0, 1, -1, 42, 255, 256, 1024,
            Int.max, Int.min, -2, -128,
            Int(bitPattern: 0x5555_5555_5555_5555), Int(bitPattern: 0xAAAA_AAAA_AAAA_AAAA),
            Int(bitPattern: 0x8000_0000_0000_0000), Int(bitPattern: 0x0000_0000_0000_0001)
        ]

        func assertSingleBitSet(_ value: Int, file: StaticString = #filePath, line: UInt = #line) {
            let bits = UInt(bitPattern: value)
            XCTAssertNotEqual(bits, 0, file: file, line: line)
            XCTAssertEqual(bits & (bits &- 1), 0, file: file, line: line)
        }

        for value in testValues {
            for distance in [0, 1, 31, 63] {
                let rotatedLeft = kk_long_rotateLeft(value, distance)
                let rotatedRight = kk_long_rotateRight(value, distance)

                XCTAssertEqual(kk_long_rotateRight(rotatedLeft, distance), value,
                    "rotateLeft→Right value=\(value), distance=\(distance)")
                XCTAssertEqual(kk_long_rotateLeft(rotatedRight, distance), value,
                    "rotateRight→Left value=\(value), distance=\(distance)")
            }

            let highest = kk_long_highestOneBit(value)
            let lowest = kk_long_lowestOneBit(value)

            if value != 0 {
                XCTAssertNotEqual(highest, 0)
                XCTAssertNotEqual(lowest, 0)
                XCTAssertTrue(isPowerOfTwo64(highest), "highestOneBit(\(value))")
                XCTAssertTrue(isPowerOfTwo64(lowest), "lowestOneBit(\(value))")
            } else {
                XCTAssertEqual(highest, 0)
                XCTAssertEqual(lowest, 0)
            }
        }
    }

    func testLowestOneBitHandlesMinimumValues() {
        XCTAssertEqual(kk_int_lowestOneBit(Int(Int32.min)), Int(Int32.min))
        XCTAssertEqual(kk_int_takeLowestOneBit(Int(Int32.min)), Int(Int32.min))
        XCTAssertEqual(kk_long_lowestOneBit(Int.min), Int.min)
        XCTAssertEqual(kk_long_takeLowestOneBit(Int.min), Int.min)
    }
}
