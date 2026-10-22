#if canImport(Testing)
import Foundation
@testable import Runtime
import Testing

// KUU-2773: expected bit patterns come from java.lang.StrictMath (fdlibm), which
// is what the JVM's kotlin.math resolves to. The host libm is off by 1-3 ULP.
@Suite
struct RuntimeMathFdlibmTests {
    @Test func testExpMatchesFdlibmBitPatterns() {
        let cases: [(Double, UInt64)] = [
            (1.0, 0x4005_BF0A_8B14_576A),
            (0.5, 0x3FFA_6129_8E1E_069C),
            (-1.0, 0x3FD7_8B56_362C_EF38),
            (10.0, 0x40D5_829D_CF95_0560),
            (0.1, 0x3FF1_AEC7_B35A_00D4),
            (-745.0, 0x1),
            (709.7, 0x7FED_75AE_7A50_EE14),
        ]
        for (x, bits) in cases {
            #expect(UInt64(bitPattern: Int64(__kk_math_exp(doubleToBits(x)))) == bits, "exp(\(x))")
        }
    }

    @Test func testAsinMatchesFdlibmBitPatterns() {
        let cases: [(Double, UInt64)] = [
            (0.5, 0x3FE0_C152_382D_7366),
            (-0.5, 0xBFE0_C152_382D_7366),
            (0.9, 0x3FF1_EA93_705F_A172),
            (0.1, 0x3FB9_A492_7603_7884),
            (0.99, 0x3FF6_DE3C_6F33_D51D),
            (-0.99, 0xBFF6_DE3C_6F33_D51D),
        ]
        for (x, bits) in cases {
            #expect(UInt64(bitPattern: Int64(__kk_math_asin(doubleToBits(x)))) == bits, "asin(\(x))")
        }
    }

    @Test func testAcosMatchesFdlibmBitPatterns() {
        let cases: [(Double, UInt64)] = [
            (0.5, 0x3FF0_C152_382D_7366),
            (-0.5, 0x4000_C152_382D_7366),
            (0.9, 0x3FDC_DD9F_8F92_2E98),
            (0.1, 0x3FF7_87B2_2CE3_F590),
            (0.99, 0x3FC2_1DF7_2882_BFD8),
            (-0.99, 0x4008_001B_E1BC_011B),
        ]
        for (x, bits) in cases {
            #expect(UInt64(bitPattern: Int64(__kk_math_acos(doubleToBits(x)))) == bits, "acos(\(x))")
        }
    }

    @Test func testSpecialValues() {
        #expect(doubleFromBits(__kk_math_exp(doubleToBits(0.0))) == 1.0)
        #expect(doubleFromBits(__kk_math_exp(doubleToBits(710.0))) == Double.infinity)
        #expect(doubleFromBits(__kk_math_exp(doubleToBits(-746.0))) == 0.0)
        #expect(doubleFromBits(__kk_math_asin(doubleToBits(1.0))) == Double.pi / 2)
        #expect(doubleFromBits(__kk_math_asin(doubleToBits(-0.0))).sign == .minus)
        #expect(doubleFromBits(__kk_math_acos(doubleToBits(1.0))) == 0.0)
        #expect(doubleFromBits(__kk_math_acos(doubleToBits(-1.0))) == Double.pi)
        #expect(doubleFromBits(__kk_math_asin(doubleToBits(1.5))).isNaN)
        #expect(doubleFromBits(__kk_math_acos(doubleToBits(-1.5))).isNaN)
    }

    private func doubleToBits(_ value: Double) -> Int {
        Int(truncatingIfNeeded: value.bitPattern)
    }

    private func doubleFromBits(_ raw: Int) -> Double {
        Double(bitPattern: UInt64(bitPattern: Int64(raw)))
    }
}
#endif
