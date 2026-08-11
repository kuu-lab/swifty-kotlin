#if canImport(Testing)
import Testing
@testable import Runtime

/// BUG-203: a boxed `Double` holding `-0.0` must stay distinguishable from
/// `null`. `-0.0`'s IEEE754 bit pattern is `runtimeNullSentinelInt`
/// (`Int64.min`), so the null-checking `kk_box_double` reports it as null;
/// statically non-null sources route to `kk_box_double_nonnull` instead.
@Suite
struct RuntimeBoxedDoubleSignedZeroTests {
    private func bits(_ value: Double) -> Int {
        Int(bitPattern: UInt(truncatingIfNeeded: value.bitPattern))
    }

    @Test
    func testBoxDoubleNonNullPreservesNegativeZero() {
        let boxed = kk_box_double_nonnull(bits(-0.0))
        #expect(boxed != runtimeNullSentinelInt)
        let unboxed = kk_unbox_double(boxed)
        #expect(unboxed == bits(-0.0))
        #expect(Double(bitPattern: UInt64(bitPattern: Int64(unboxed))).sign == .minus)
    }

    @Test
    func testBoxDoubleNonNullRoundTripsOrdinaryValues() {
        for value in [0.0, 1.5, -3.25, Double.infinity] {
            let boxed = kk_box_double_nonnull(bits(value))
            #expect(kk_unbox_double(boxed) == bits(value))
        }
    }

    @Test
    func testBoxDoubleKeepsNullSentinelForNullableSources() {
        #expect(kk_box_double(runtimeNullSentinelInt) == runtimeNullSentinelInt)
    }

    @Test
    func testBoxDoublePassesThroughAlreadyBoxedValue() {
        let boxed = kk_box_double_nonnull(bits(2.5))
        #expect(kk_box_double(boxed) == boxed)
    }

    @Test
    func testBoxedDoubleEqualsRawDoubleWord() {
        let boxed = kk_box_double_nonnull(bits(1.5))
        #expect(runtimeValuesEqual(boxed, bits(1.5)))
        #expect(!runtimeValuesEqual(boxed, bits(2.5)))
        #expect(!runtimeValuesEqual(kk_box_double_nonnull(bits(0.0)), bits(-0.0)))
    }

    @Test
    func testBoxedDoubleEqualityUsesBitPattern() {
        let negativeZero = kk_box_double_nonnull(bits(-0.0))
        let positiveZero = kk_box_double_nonnull(bits(0.0))
        let firstNaN = kk_box_double_nonnull(bits(Double.nan))
        let secondNaN = kk_box_double_nonnull(bits(Double.nan))

        #expect(!runtimeValuesEqual(negativeZero, positiveZero))
        #expect(runtimeValuesEqual(firstNaN, secondNaN))
        #expect(runtimeValuesEqual(negativeZero, kk_box_double_nonnull(bits(-0.0))))
    }

    /// A bare `Int64.min` word reaching equality is treated as null, not as a
    /// raw `-0.0`: the ambiguity is resolved in the compiler instead, by
    /// boxing floating-point arguments at erased `T` parameters.
    @Test
    func testBoxedNegativeZeroIsNotEqualToNullSentinel() {
        let boxed = kk_box_double_nonnull(bits(-0.0))
        #expect(!runtimeValuesEqual(boxed, runtimeNullSentinelInt))
    }

    @Test
    func testDoubleArrayToListBoxesNegativeZeroElements() {
        let array = RuntimeArrayBox(length: 2)
        array.elements[0] = bits(-0.0)
        array.elements[1] = bits(1.0)
        let list = kk_doubleArray_toList(registerRuntimeObject(array))
        let elements = try? #require(runtimeListBox(from: list)).elements
        #expect(elements?.first != runtimeNullSentinelInt)
        #expect(elements.map { $0.map { kk_unbox_double($0) } } == [bits(-0.0), bits(1.0)])
    }
}
#endif
