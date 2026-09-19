#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct RuntimeBoxingTests {
    // MARK: - kk_box_int / kk_unbox_int

    @Test
    func testBoxAndUnboxIntRoundTrip() {
        let boxed = kk_box_int(42)
        let unboxed = kk_unbox_int(boxed)
        #expect(unboxed == 42)
    }

    @Test
    func testBoxIntNullSentinelPassesThrough() {
        let sentinel = Int(Int64.min)
        let result = kk_box_int(sentinel)
        #expect(result == sentinel)
    }

    @Test
    func testUnboxIntNullSentinelReturnsZero() {
        let sentinel = Int(Int64.min)
        let result = kk_unbox_int(sentinel)
        #expect(result == 0)
    }

    @Test
    func testUnboxIntNonBoxedValueReturnsValueUnchanged() {
        // A small integer that was never boxed should pass through
        let result = kk_unbox_int(7)
        #expect(result == 7)
    }

    @Test
    func testBoxIntNegativeValue() {
        let boxed = kk_box_int(-100)
        let unboxed = kk_unbox_int(boxed)
        #expect(unboxed == -100)
    }

    @Test
    func testBoxIntZero() {
        let boxed = kk_box_int(0)
        let unboxed = kk_unbox_int(boxed)
        #expect(unboxed == 0)
    }

    @Test
    func testBoxedZeroMatchesRawZeroAsMapKey() {
        let map = registerRuntimeObject(RuntimeMapBox(keys: [kk_box_int(0)], values: [123]))
        #expect(kk_map_get(map, 0) == 123)
    }

    // MARK: - kk_box_float / kk_unbox_float

    @Test
    func testBoxAndUnboxFloatRoundTrip() {
        let bits = Int(Float(1.5).bitPattern)
        let boxed = kk_box_float(bits)
        #expect(kk_unbox_float(boxed) == bits)
    }

    @Test
    func testBoxFloatDoesNotPassThroughAnUnrelatedPrimitiveBox() {
        let unrelatedBox = kk_box_int(1)
        let expectedBits = Int(Float(bitPattern: UInt32(truncatingIfNeeded: unrelatedBox)).bitPattern)
        let boxedFloat = kk_box_float(unrelatedBox)

        #expect(kk_unbox_float(boxedFloat) == expectedBits)
    }

    // MARK: - kk_box_bool / kk_unbox_bool

    @Test
    func testBoxAndUnboxBoolTrueRoundTrip() {
        let boxed = kk_box_bool(1)
        let unboxed = kk_unbox_bool(boxed)
        #expect(unboxed == 1)
    }

    @Test
    func testBoxAndUnboxBoolFalseRoundTrip() {
        let boxed = kk_box_bool(0)
        let unboxed = kk_unbox_bool(boxed)
        #expect(unboxed == 0)
    }

    @Test
    func testBoxBoolNullSentinelPassesThrough() {
        let sentinel = Int(Int64.min)
        let result = kk_box_bool(sentinel)
        #expect(result == sentinel)
    }

    @Test
    func testUnboxBoolNullSentinelReturnsZero() {
        let sentinel = Int(Int64.min)
        let result = kk_unbox_bool(sentinel)
        #expect(result == 0)
    }

    @Test
    func testUnboxBoolNonBoxedNonZeroReturnsOne() {
        // A non-zero non-boxed value should return 1 (truthy)
        let result = kk_unbox_bool(42)
        #expect(result == 1)
    }

    @Test
    func testUnboxBoolNonBoxedZeroReturnsZero() {
        // Unboxing 0 that was never boxed returns 0 (nil pointer guard path)
        let result = kk_unbox_bool(0)
        #expect(result == 0)
    }

    @Test
    func testBoxBoolPassesThroughAlreadyBoxedFalse() {
        let boxed = kk_box_bool(0)
        let doubleBoxed = kk_box_bool(boxed)
        #expect(kk_unbox_bool(doubleBoxed) == 0)
    }

    @Test
    func testBoxBoolPassesThroughAlreadyBoxedTrue() {
        let boxed = kk_box_bool(1)
        let doubleBoxed = kk_box_bool(boxed)
        #expect(kk_unbox_bool(doubleBoxed) == 1)
    }

    // MARK: - Multiple boxes

    // MARK: - kk_unbox_long sentinel edge case

    @Test
    func testUnboxLongRawLongMinReturnsLongMin() {
        // runtimeNullSentinelInt == Int64.min == Long.MIN_VALUE.
        // Passing Long.MIN_VALUE as a raw (unboxed) intptr_t must return Long.MIN_VALUE,
        // not 0. This is the passthrough path: Int.min is never a heap pointer.
        #expect(kk_unbox_long(Int.min) == Int.min)
    }

    @Test
    func testMultipleBoxedIntsAreIndependent() {
        let boxed1 = kk_box_int(10)
        let boxed2 = kk_box_int(20)
        #expect(kk_unbox_int(boxed1) == 10)
        #expect(kk_unbox_int(boxed2) == 20)
    }

    // MARK: - Statically-known primitive fast paths

    @Test
    func testStaticIntBoxUsesTaggedHandleAndLegacyUnbox() {
        let boxed = kk_box_int_static(42)

        #expect(runtimePrimitiveBoxBasePointer(from: boxed) != nil)
        #expect(kk_unbox_int_static(boxed) == 42)
        #expect(kk_unbox_int(boxed) == 42)
        #expect(kk_unbox_int_static(5) == 5)
        #expect(runtimeElementToString(boxed) == "42")
        #expect(runtimeValuesEqual(boxed, kk_box_int(42)))
    }

    @Test
    func testStaticPrimitiveBoxesPreserveTypedPayloads() {
        let longBox = kk_box_long_nonnull_static(Int.min)
        let doubleBits = Int(bitPattern: UInt(0x8000_0000_0000_0000))
        let doubleBox = kk_box_double_nonnull_static(doubleBits)
        let boolBox = kk_box_bool_static(1)
        let charBox = kk_box_char_static(0x1F600)

        #expect(kk_unbox_long_static(longBox) == Int.min)
        #expect(kk_unbox_double_static(doubleBox) == doubleBits)
        #expect(kk_unbox_bool_static(boolBox) == 1)
        #expect(kk_unbox_char_static(charBox) == 0x1F600)
    }

    @Test
    func testStaticNullableBoxesKeepNullSentinel() {
        let sentinel = Int(Int64.min)

        #expect(kk_box_int_static(sentinel) == sentinel)
        #expect(kk_box_long_static(sentinel) == sentinel)
        #expect(kk_box_double_static(sentinel) == sentinel)
        #expect(kk_unbox_int_static(sentinel) == 0)
        #expect(kk_unbox_long_static(sentinel) == Int.min)
        #expect(kk_unbox_double_static(sentinel) == 0)
    }

    @Test
    func testStaticBoxPreservesRegisteredRuntimeObjectHandle() {
        let range = kk_op_rangeTo(1, 3)

        #expect(kk_box_int_static(range) == range)
        #expect(kk_range_first(range) == 1)
        #expect(kk_range_last(range) == 3)
    }

    /// An Int that never went through `kk_box_*_static` can still match the
    /// tagged-handle bit pattern (a hash code, uninitialized memory, or any
    /// other value flowing through a static unbox call site) — the pattern
    /// alone is not collision-proof, so `runtimePrimitiveBoxBasePointer`
    /// returns a non-nil pointer for it. `kk_unbox_*_static` must still
    /// reject it via the registry check rather than treat it as a live
    /// handle: doing otherwise reinterprets unrelated bits as an
    /// `Unmanaged<AnyObject>` and crashes (observed as `swift_retain`
    /// faulting on a bogus pointer during a stdlib companion's static init
    /// in CI). Without the registry check, this test crashes the process
    /// rather than failing an expectation — `fakeBaseBits` is deliberately an
    /// unmapped address, not an arbitrary choice.
    @Test
    func testUnboxStaticRejectsUnregisteredTagCollision() {
        let fakeBaseBits: UInt = 0x0000_1234_5678_0000
        let fakeTagged = Int(bitPattern: fakeBaseBits | runtimePrimitiveBoxTag)

        #expect(runtimePrimitiveBoxBasePointer(from: fakeTagged) != nil)
        #expect(kk_unbox_int_static(fakeTagged) == fakeTagged)
        #expect(kk_unbox_double_static(fakeTagged) == fakeTagged)
    }
}
#endif
