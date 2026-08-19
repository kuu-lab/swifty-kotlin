#if canImport(Testing)
import Testing
@testable import Runtime

/// Tests for the floating-point bit-pattern bridges.
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
        #expect(__kk_float_toRawBits(Self.abiBits(-1.0)) == Int(Int32(bitPattern: 0xBF80_0000)))
        #expect(__kk_float_toRawBits(Self.abiBits(-0.0)) == Int(Int32(bitPattern: 0x8000_0000)))
        #expect(__kk_float_toRawBits(Self.abiBits(-1.0)) < 0)
        #expect(__kk_float_toRawBits(Self.abiBits(-0.0)) < 0)
    }

    @Test
    func testToRawBitsKeepsPositiveFloatsUnchanged() {
        #expect(__kk_float_toRawBits(Self.abiBits(1.0)) == 1_065_353_216)
        #expect(__kk_float_toRawBits(Self.abiBits(0.0)) == 0)
    }

    @Test
    func testToBitsSignExtendsAndCanonicalizesNaN() {
        #expect(__kk_float_toBits(Self.abiBits(-1.0)) == Int(Int32(bitPattern: 0xBF80_0000)))
        #expect(__kk_float_toBits(Self.abiBits(1.0)) == 1_065_353_216)
        #expect(__kk_float_toBits(Self.abiBits(Float.nan)) == 0x7FC0_0000)
    }

    @Test
    func testDoublePreservesSignedZeroInfinityAndNaNPayload() {
        let negativeZero = Int(bitPattern: UInt(0x8000_0000_0000_0000 as UInt64))
        let positiveInfinity = Int(bitPattern: UInt(0x7FF0_0000_0000_0000 as UInt64))
        let payload = Int(bitPattern: UInt(0x7FF0_0000_0000_0123 as UInt64))

        #expect(__kk_double_toRawBits(negativeZero) == negativeZero)
        #expect(__kk_double_toRawBits(positiveInfinity) == positiveInfinity)
        #expect(__kk_double_toRawBits(payload) == payload)
        #expect(__kk_double_toBits(payload) == Int(bitPattern: UInt(0x7FF8_0000_0000_0000 as UInt64)))
    }
}
#endif
