#if canImport(Testing)
import Testing
@testable import Runtime

/// Tests for the Float bit-pattern bridges (`kk_float_toBits`, `kk_float_toRawBits`,
/// `kk_float_fromBits`).
///
/// Float values cross the C ABI as a zero-extended 32-bit pattern, while Kotlin
/// `Int` is transported sign-extended. The bridges must therefore sign-extend on
/// the way out and re-widen on the way in, otherwise `(-1.0f).toRawBits()` is
/// observed as a positive value and sign-bit checks such as `toRawBits() < 0`
/// silently break.
@Suite
struct RuntimeFloatBitsTests {

    private static func abiBits(_ value: Float) -> Int {
        Int(UInt32(value.bitPattern))
    }

    @Test
    func testToRawBitsSignExtendsNegativeFloats() {
        #expect(kk_float_toRawBits(Self.abiBits(-1.0)) == Int(Int32(bitPattern: 0xBF80_0000)))
        #expect(kk_float_toRawBits(Self.abiBits(-0.0)) == Int(Int32(bitPattern: 0x8000_0000)))
        #expect(kk_float_toRawBits(Self.abiBits(-1.0)) < 0)
        #expect(kk_float_toRawBits(Self.abiBits(-0.0)) < 0)
    }

    @Test
    func testToRawBitsKeepsPositiveFloatsUnchanged() {
        #expect(kk_float_toRawBits(Self.abiBits(1.0)) == 1_065_353_216)
        #expect(kk_float_toRawBits(Self.abiBits(0.0)) == 0)
    }

    @Test
    func testToBitsSignExtendsAndCanonicalizesNaN() {
        #expect(kk_float_toBits(Self.abiBits(-1.0)) == Int(Int32(bitPattern: 0xBF80_0000)))
        #expect(kk_float_toBits(Self.abiBits(1.0)) == 1_065_353_216)
        #expect(kk_float_toBits(Self.abiBits(Float.nan)) == 0x7FC0_0000)
    }

    @Test
    func testFromBitsRoundTripsNegativeFloats() {
        for value in [-1.0 as Float, -0.0, 0.0, 1.0, Float.infinity, -Float.infinity] {
            let raw = kk_float_toRawBits(Self.abiBits(value))
            #expect(kk_float_fromBits(raw) == Self.abiBits(value))
        }
    }
}
#endif
