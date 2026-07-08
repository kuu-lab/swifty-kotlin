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
    func testPrimitiveNameLookupUsesRuntimeAliases() {
        for (primitive, boxName, unboxName) in primitiveExpectations {
            #expect(BoxingCalleeTable.boxCalleeName(for: primitive) == boxName)
            #expect(BoxingCalleeTable.unboxCalleeName(for: primitive) == unboxName)
            #expect(ABILoweringPass.primitiveBoxingCalleeName(for: primitive) == boxName)
            #expect(ABILoweringPass.primitiveUnboxingCalleeName(for: primitive) == unboxName)
        }
    }

    @Test
    func testInternedTypeLookupUsesSharedTable() {
        let interner = StringInterner()
        let types = TypeSystem()
        let table = BoxingCalleeTable(interner: interner)

        for (primitive, boxName, unboxName) in primitiveExpectations {
            let type = types.make(.primitive(primitive, .nonNull))
            let boxCallee = table.boxCallee(for: type, types: types, requireNonNull: true)
            let unboxCallee = table.unboxCallee(for: type, types: types, requireNonNull: true)
            #expect(boxCallee.map(interner.resolve) == boxName)
            #expect(unboxCallee.map(interner.resolve) == unboxName)
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
