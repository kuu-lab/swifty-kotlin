#if canImport(Testing)
import Testing
@testable import Runtime

/// Regression coverage for the ULong sign-misinterpretation bug found while
/// working on KSP-466 (kotlin.random.Random.nextULong()): values with the
/// high bit set (>= 2^63) were compared and stringified as if they were
/// signed Int64, because kk_op_lt/le/gt/ge and kk_any_to_string's default tag
/// both reinterpret the raw 64-bit container as signed. UInt/UByte/UShort are
/// always zero-extended into this container and so never exhibit the bug;
/// ULong is the one unsigned type that spans the full 64 bits.
@Suite
struct RuntimeUnsignedComparisonAndToStringTests {
    // A ULong whose bit pattern is negative when read as a signed Int64:
    // 17663719463477156090 as UInt64 == -783024610232395526 as Int64.
    private let highBitSet = Int(bitPattern: 17_663_719_463_477_156_090 as UInt)
    private let small = 5

    // MARK: - kk_op_u{lt,le,gt,ge}

    @Test
    func testUnsignedLessThanUsesFullBitWidth() {
        #expect(kk_op_ult(small, highBitSet) == 1)
        #expect(kk_op_ult(highBitSet, small) == 0)
        #expect(kk_op_ult(highBitSet, highBitSet) == 0)
    }

    @Test
    func testUnsignedLessOrEqualUsesFullBitWidth() {
        #expect(kk_op_ule(small, highBitSet) == 1)
        #expect(kk_op_ule(highBitSet, small) == 0)
        #expect(kk_op_ule(highBitSet, highBitSet) == 1)
    }

    @Test
    func testUnsignedGreaterThanUsesFullBitWidth() {
        #expect(kk_op_ugt(highBitSet, small) == 1)
        #expect(kk_op_ugt(small, highBitSet) == 0)
        #expect(kk_op_ugt(highBitSet, highBitSet) == 0)
    }

    @Test
    func testUnsignedGreaterOrEqualUsesFullBitWidth() {
        #expect(kk_op_uge(highBitSet, small) == 1)
        #expect(kk_op_uge(small, highBitSet) == 0)
        #expect(kk_op_uge(highBitSet, highBitSet) == 1)
        // Any ULong is always >= 0uL by definition.
        #expect(kk_op_uge(highBitSet, 0) == 1)
    }

    @Test
    func testUnsignedComparisonAgreesWithSignedForSmallValues() {
        // For values that fit the signed range, unsigned and signed ordering
        // must agree — the fix must not change behaviour for the common case.
        #expect(kk_op_ult(3, 5) == kk_op_lt(3, 5))
        #expect(kk_op_ule(3, 5) == kk_op_le(3, 5))
        #expect(kk_op_ugt(5, 3) == kk_op_gt(5, 3))
        #expect(kk_op_uge(5, 3) == kk_op_ge(5, 3))
    }

    @Test
    func testUnsignedComparisonAtMaxValue() {
        let maxULong = Int(bitPattern: UInt.max)
        #expect(kk_op_uge(maxULong, 0) == 1)
        #expect(kk_op_ugt(maxULong, highBitSet) == 1)
        #expect(kk_op_ult(maxULong, highBitSet) == 0)
    }

    // MARK: - kk_any_to_string tag 7 (ULong)

    @Test
    func testAnyToStringTag7RendersUnsignedDecimal() {
        let rendered = extractString(from: kk_any_to_string(highBitSet, 7))
        #expect(rendered == "17663719463477156090")
    }

    @Test
    func testAnyToStringTag7MatchesTag1ForSmallValues() {
        // Small values (that fit the signed range) must render identically
        // under both the generic (tag 1) and ULong-aware (tag 7) paths.
        let taggedAsInt = extractString(from: kk_any_to_string(small, 1))
        let taggedAsULong = extractString(from: kk_any_to_string(small, 7))
        #expect(taggedAsInt == taggedAsULong)
    }

    @Test
    func testAnyToStringTag7DoesNotCollideWithNullSentinel() {
        // 2^63 has the exact same 64-bit pattern as Int.min, which
        // kk_any_to_string uses as its "null" sentinel. Tag 7 must be decoded
        // before that check fires, or a perfectly valid ULong would print as
        // the string "null" instead of "9223372036854775808".
        let boundary = Int.min
        let rendered = extractString(from: kk_any_to_string(boundary, 7))
        #expect(rendered == "9223372036854775808")
    }

    @Test
    func testAnyToStringTag7RendersMaxValue() {
        let maxULong = Int(bitPattern: UInt.max)
        let rendered = extractString(from: kk_any_to_string(maxULong, 7))
        #expect(rendered == "18446744073709551615")
    }

    @Test
    func testAnyToStringTag1StillReportsNullForGenuineNullSentinel() {
        // Sanity check that the tag-7 fix did not disturb the existing
        // null-sentinel behaviour for the untagged/default (tag 1) path.
        let rendered = extractString(from: kk_any_to_string(runtimeNullSentinelInt, 1))
        #expect(rendered == "null")
    }
}
#endif
