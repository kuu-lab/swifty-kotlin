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
    func testNonNullDoubleUnboxingPreservesRawAndBoxedBits() {
        for value in [-0.0, 0.0, 1.5, -3.25, Double.infinity, -Double.infinity, Double.nan] {
            let raw = bits(value)
            #expect(kk_unbox_double_nonnull(raw) == raw)
            #expect(kk_unbox_double_nonnull_static(raw) == raw)
            for boxed in [kk_box_double_nonnull(raw), kk_box_double_nonnull_static(raw)] {
                #expect(kk_unbox_double_nonnull(boxed) == raw)
                #expect(kk_unbox_double_nonnull_static(boxed) == raw)
            }
        }
        // Legacy unboxing must also preserve a raw -0.0 word; its bits
        // cannot be distinguished from the nullable sentinel at this boundary.
        #expect(kk_unbox_double(runtimeNullSentinelInt) == runtimeNullSentinelInt)
        #expect(kk_unbox_double_static(runtimeNullSentinelInt) == runtimeNullSentinelInt)
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
    func testBoxedDoubleEqualityCanonicalizesNaNAndPreservesSignedZero() {
        let negativeZero = kk_box_double_nonnull(bits(-0.0))
        let positiveZero = kk_box_double_nonnull(bits(0.0))
        let canonicalNaN = kk_box_double_nonnull(bits(Double.nan))
        let positivePayloadNaN = kk_box_double_nonnull(Int(bitPattern: UInt(0x7ff8_0000_0000_0001)))
        let negativePayloadNaN = kk_box_double_nonnull(Int(bitPattern: UInt(0xfff8_0000_0000_0042)))

        #expect(!runtimeValuesEqual(negativeZero, positiveZero))
        #expect(runtimeValuesEqual(canonicalNaN, positivePayloadNaN))
        #expect(runtimeValuesEqual(canonicalNaN, negativePayloadNaN))
        #expect(runtimeValuesEqual(positivePayloadNaN, bits(Double(bitPattern: 0xfff8_0000_0000_0042))))
        #expect(runtimeValuesEqual(negativeZero, kk_box_double_nonnull(bits(-0.0))))
    }

    @Test
    func testBoxedFloatEqualityCanonicalizesNaNPayloads() {
        let firstNaN = kk_box_float(0x7fc0_0001)
        let secondNaN = kk_box_float(Int(Int32(bitPattern: 0xffc0_0042)))
        let rawNegativeNaN = Int(Int32(bitPattern: 0xffc0_0042))

        #expect(runtimeValuesEqual(firstNaN, secondNaN))
        #expect(runtimeValuesEqual(firstNaN, rawNegativeNaN))
        #expect(!runtimeValuesEqual(kk_box_float(Int(Int32.min)), kk_box_float(0)))
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

    @Test
    func testCharBooleanAndFloatArrayToListBoxElements() {
        let charArray = RuntimeArrayBox(length: 2)
        charArray.elements[0] = 97
        charArray.elements[1] = 90
        let charList = kk_charArray_toList(registerRuntimeObject(charArray))
        let charElements = runtimeListBox(from: charList)?.elements ?? []
        #expect(charElements.map(kk_unbox_char) == [97, 90])

        let booleanArray = RuntimeArrayBox(length: 2)
        booleanArray.elements[0] = 1
        booleanArray.elements[1] = 0
        let booleanList = kk_booleanArray_toList(registerRuntimeObject(booleanArray))
        let booleanElements = runtimeListBox(from: booleanList)?.elements ?? []
        #expect(booleanElements.map(kk_unbox_bool) == [1, 0])

        let floatArray = RuntimeArrayBox(length: 2)
        floatArray.elements[0] = Int(Float(3.5).bitPattern)
        floatArray.elements[1] = Int(Float(-4.5).bitPattern)
        let floatList = kk_floatArray_toList(registerRuntimeObject(floatArray))
        let floatElements = runtimeListBox(from: floatList)?.elements ?? []
        #expect(floatElements.map(kk_unbox_float) == [Int(Float(3.5).bitPattern), Int(Float(-4.5).bitPattern)])
    }
}
#endif
