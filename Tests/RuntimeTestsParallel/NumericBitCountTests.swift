#if canImport(Testing)
import Testing
@testable import Runtime

// KSP-643: countOneBits / countLeadingZeroBits / countTrailingZeroBits are implemented in
// bundled Kotlin source (Stdlib/kotlin/BitOperations.kt); their runtime entry points are gone.
// The remaining bit-manipulation entry points are covered here.
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
