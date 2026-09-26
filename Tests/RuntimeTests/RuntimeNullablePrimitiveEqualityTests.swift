#if canImport(Testing)
@testable import Runtime
import Testing

/// `kk_nullable_primitive_eq`/`_ne` back the compiler's null-aware equality
/// for `Long?`/`ULong?`/`Double?`/`Float?` (OperatorLoweringPass routes these
/// there instead of `kk_structural_eq`/`ne`): those are the only primitives
/// whose full raw (unboxed) value range coincides with the runtime null
/// sentinel (`Long.MIN_VALUE`, `ULong` `2^63`, `-0.0`'s bit pattern), so
/// "raw value equals the sentinel implies null" cannot tell a genuine null
/// apart from a genuine value sharing that bit pattern — nullness has to
/// come from each operand's own boxing state instead.
@Suite(.serialized, .runtimeIsolation(.all))
struct RuntimeNullablePrimitiveEqualityTests {
    private let sentinel = Int(Int64.min)

    @Test
    func bothNullIsEqual() {
        #expect(kk_nullable_primitive_eq(sentinel, sentinel, 1) == 1)
        #expect(kk_nullable_primitive_ne(sentinel, sentinel, 1) == 0)
    }

    @Test
    func nullNeverEqualsNonNullSentinelCollidingValue() {
        // The raw literal `Long.MIN_VALUE` shares its bit pattern with the
        // null sentinel, but the peer is statically non-null (peerIsNullable
        // == 0), so it must never be treated as null.
        #expect(kk_nullable_primitive_eq(sentinel, sentinel, 0) == 0)
        #expect(kk_nullable_primitive_ne(sentinel, sentinel, 0) == 1)
    }

    @Test
    func boxedLongMinValueEqualsRawLongMinValueLiteral() {
        // kk_box_long treats the sentinel as "genuinely null" and passes it
        // through unboxed — the compiler instead selects kk_box_long_nonnull
        // for a statically non-null source (see BoxingCalleeTable), which
        // has no such passthrough and always allocates a real box.
        let boxed = kk_box_long_nonnull(sentinel)
        #expect(boxed != sentinel, "a genuine boxed Long.MIN_VALUE must not be the bare sentinel bit pattern")
        #expect(kk_nullable_primitive_eq(boxed, sentinel, 0) == 1)
        #expect(kk_nullable_primitive_ne(boxed, sentinel, 0) == 0)
    }

    @Test
    func nullNeverEqualsBoxedLongMinValue() {
        let boxed = kk_box_long_nonnull(sentinel)
        #expect(kk_nullable_primitive_eq(sentinel, boxed, 1) == 0)
        #expect(kk_nullable_primitive_ne(sentinel, boxed, 1) == 1)
    }

    @Test
    func twoBoxedLongMinValuesAreEqualDespiteDistinctInstances() {
        let first = kk_box_long_nonnull(sentinel)
        let second = kk_box_long_nonnull(sentinel)
        #expect(first != second, "each kk_box_long_nonnull call allocates a fresh box")
        #expect(kk_nullable_primitive_eq(first, second, 1) == 1)
    }

    @Test
    func ordinaryNonNullValuesCompareNormally() {
        let boxedFive = kk_box_long_nonnull(5)
        #expect(kk_nullable_primitive_eq(boxedFive, 5, 0) == 1)
        #expect(kk_nullable_primitive_eq(boxedFive, 6, 0) == 0)
        #expect(kk_nullable_primitive_ne(boxedFive, 6, 0) == 1)
    }

    @Test
    func doubleNegativeZeroSentinelCollision() {
        // -0.0's bit pattern is exactly Int64.min (the null sentinel).
        // kk_box_double also passes the sentinel through unboxed, so use
        // kk_box_double_nonnull, matching what the compiler selects for a
        // statically non-null source.
        let negativeZeroBits = Int(bitPattern: UInt(Double(-0.0).bitPattern))
        #expect(negativeZeroBits == sentinel)
        let boxedNegativeZero = kk_box_double_nonnull(negativeZeroBits)
        #expect(kk_nullable_primitive_eq(boxedNegativeZero, negativeZeroBits, 0) == 1)
        #expect(kk_nullable_primitive_eq(sentinel, boxedNegativeZero, 1) == 0, "null must not equal a boxed -0.0")
    }
}
#endif
