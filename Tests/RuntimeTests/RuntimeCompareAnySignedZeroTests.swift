#if canImport(Testing)
import Testing
@testable import Runtime

/// KUU-637: `kk_compare_any` (generic `Comparable` `minOf`/`maxOf`) must follow
/// the `Double.compare` / `Float.compare` total order, where `-0.0` sorts
/// before `0.0`. Collection comparisons already did; the type-erased path
/// used to treat IEEE equality as compare-equal.
@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeCompareAnySignedZeroTests {
    private func boxDouble(_ value: Double) -> Int {
        kk_box_double_nonnull(Int(bitPattern: UInt(truncatingIfNeeded: value.bitPattern)))
    }

    private func boxFloat(_ value: Float) -> Int {
        kk_box_float(Int(value.bitPattern))
    }

    @Test
    func testCompareAnyOrdersBoxedDoubleSignedZeros() {
        let negativeZero = boxDouble(-0.0)
        let positiveZero = boxDouble(0.0)

        #expect(kk_compare_any(negativeZero, positiveZero) == -1)
        #expect(kk_compare_any(positiveZero, negativeZero) == 1)
        #expect(kk_compare_any(positiveZero, boxDouble(0.0)) == 0)
        #expect(kk_compare_any(negativeZero, boxDouble(-0.0)) == 0)
    }

    @Test
    func testCompareAnyOrdersBoxedFloatSignedZeros() {
        let negativeZero = boxFloat(-0.0)
        let positiveZero = boxFloat(0.0)

        #expect(kk_compare_any(negativeZero, positiveZero) == -1)
        #expect(kk_compare_any(positiveZero, negativeZero) == 1)
        #expect(kk_compare_any(positiveZero, boxFloat(0.0)) == 0)
        #expect(kk_compare_any(negativeZero, boxFloat(-0.0)) == 0)
    }
}
#endif
