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
}
#endif
