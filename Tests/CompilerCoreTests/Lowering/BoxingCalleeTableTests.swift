#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct BoxingCalleeTableTests {
    private let primitiveExpectations: [(PrimitiveType, String, String)] = [
        (.int, "kk_box_int", "kk_unbox_int"),
        (.uint, "kk_box_int", "kk_unbox_int"),
        (.ubyte, "kk_box_int", "kk_unbox_int"),
        (.ushort, "kk_box_int", "kk_unbox_int"),
        (.long, "kk_box_long", "kk_unbox_long"),
        (.ulong, "kk_box_ulong", "kk_unbox_ulong"),
        (.boolean, "kk_box_bool", "kk_unbox_bool"),
        (.float, "kk_box_float", "kk_unbox_float"),
        (.double, "kk_box_double", "kk_unbox_double"),
        (.char, "kk_box_char", "kk_unbox_char"),
    ]

    @Test
    func testPrimitiveNameLookupUsesRuntimeTable() {
        for (primitive, boxName, unboxName) in primitiveExpectations {
            #expect(BoxingCalleeTable.boxCalleeName(for: primitive) == boxName)
            #expect(BoxingCalleeTable.unboxCalleeName(for: primitive) == unboxName)
        }
    }

    /// `.long`/`.ulong` box callees when the source TypeKind is provably
    /// non-null: `runtimeNullSentinelInt` (Int64.min) collides bit-for-bit
    /// with a legitimate value of those two 64-bit types (Long.MIN_VALUE /
    /// ULong 2^63), so a non-null source routes to a callee that boxes
    /// unconditionally instead of one that treats that bit pattern as null.
    private let nonNullBoxOverrides: [PrimitiveType: String] = [
        .long: "kk_box_long_nonnull",
        .ulong: "kk_box_ulong_nonnull",
    ]

    @Test
    func testInternedTypeLookupUsesSharedTable() {
        let interner = StringInterner()
        let types = TypeSystem()
        let table = BoxingCalleeTable(interner: interner)

        for (primitive, boxName, unboxName) in primitiveExpectations {
            let type = types.make(.primitive(primitive, .nonNull))
            let boxCallee = table.boxCallee(for: type, types: types, requireNonNull: true)
            let unboxCallee = table.unboxCallee(for: type, types: types, requireNonNull: true)
            let expectedBoxName = nonNullBoxOverrides[primitive] ?? boxName
            #expect(boxCallee.map(interner.resolve) == expectedBoxName)
            #expect(unboxCallee.map(interner.resolve) == unboxName)
        }

        // Nullable Long/ULong sources must keep resolving to the default
        // (null-checking) box callee, not the non-null override: the source
        // might genuinely be null at runtime, and only the default callee
        // preserves that by passing the sentinel through unboxed.
        for (primitive, boxName, _) in primitiveExpectations where nonNullBoxOverrides[primitive] != nil {
            let nullableType = types.make(.primitive(primitive, .nullable))
            let boxCallee = table.boxCallee(for: nullableType, types: types, requireNonNull: false)
            #expect(boxCallee.map(interner.resolve) == boxName)
        }

        let nullableInt = types.make(.primitive(.int, .nullable))
        if let callee = table.boxCallee(for: nullableInt, types: types, requireNonNull: true) {
            Issue.record("Nullable Int should not satisfy requireNonNull boxing lookup: \(interner.resolve(callee))")
        }
        if let callee = table.unboxCallee(for: nullableInt, types: types, requireNonNull: true) {
            Issue.record("Nullable Int should not satisfy requireNonNull unboxing lookup: \(interner.resolve(callee))")
        }

        let stringType = types.make(.stringStruct(.nonNull))
        if let callee = table.boxCallee(for: stringType, types: types, requireNonNull: true) {
            Issue.record("String is not primitive-boxed by the runtime table: \(interner.resolve(callee))")
        }
        if let callee = table.unboxCallee(for: stringType, types: types, requireNonNull: true) {
            Issue.record("String is not primitive-unboxed by the runtime table: \(interner.resolve(callee))")
        }
    }
}
#endif
