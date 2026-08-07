#if canImport(Testing)
import Testing
@testable import Runtime

/// BUG-160: `Double`/`Float`.`compareTo` must follow the `Double.compare` /
/// `Float.compare` total order, where `-0.0` sorts before `0.0` (IEEE equality
/// treats them as equal).
@Suite
struct RuntimePrimitiveCompareToSignedZeroTests {
    private static let doubleKind: Int32 = 7
    private static let floatKind: Int32 = 6

    private func compareDoubles(_ lhs: Double, _ rhs: Double) -> Int {
        kk_primitive_compareTo(kk_double_to_bits(lhs), kk_double_to_bits(rhs), Self.doubleKind)
    }

    private func compareFloats(_ lhs: Float, _ rhs: Float) -> Int {
        kk_primitive_compareTo(kk_float_to_bits(lhs), kk_float_to_bits(rhs), Self.floatKind)
    }

    @Test
    func testDoubleSignedZeroTotalOrder() {
        #expect(compareDoubles(-0.0, 0.0) == -1)
        #expect(compareDoubles(0.0, -0.0) == 1)
        #expect(compareDoubles(0.0, 0.0) == 0)
        #expect(compareDoubles(-0.0, -0.0) == 0)
    }

    @Test
    func testFloatSignedZeroTotalOrder() {
        #expect(compareFloats(-0.0, 0.0) == -1)
        #expect(compareFloats(0.0, -0.0) == 1)
        #expect(compareFloats(0.0, 0.0) == 0)
        #expect(compareFloats(-0.0, -0.0) == 0)
    }

    @Test
    func testNonZeroAndNaNOrderingUnchanged() {
        #expect(compareDoubles(-1.0, 0.0) == -1)
        #expect(compareDoubles(1.0, -0.0) == 1)
        #expect(compareDoubles(1.0, 1.0) == 0)
        #expect(compareDoubles(.nan, 0.0) == 1)
        #expect(compareDoubles(0.0, .nan) == -1)
        #expect(compareDoubles(.nan, .nan) == 0)
        #expect(compareDoubles(-.infinity, .infinity) == -1)
    }
}
#endif
