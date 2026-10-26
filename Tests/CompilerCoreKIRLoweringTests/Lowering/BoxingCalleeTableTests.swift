#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct BoxingCalleeTableTests {
    private let primitives: [PrimitiveType] = [
        .int, .byte, .short, .uint, .ubyte, .ushort,
        .long, .ulong, .boolean, .float, .double, .char,
    ]

    @Test
    func testPrimitiveNameLookupUsesRuntimeTable() throws {
        for primitive in primitives {
            let box = try loweringBoxingABI(.box, for: primitive)
            let unbox = try loweringBoxingABI(.unbox, for: primitive)
            #expect(BoxingCalleeTable.boxCalleeName(for: primitive) == box.name)
            #expect(BoxingCalleeTable.unboxCalleeName(for: primitive) == unbox.name)
            for abi in [box, unbox] {
                #expect(abi.parameters.count == 1 && abi.parameters.first?.type == .intptr)
                #expect(abi.returnType == .intptr)
                #expect(!abi.isThrowing)
            }
        }
    }

    @Test
    func testInternedTypeLookupUsesSharedTable() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let table = BoxingCalleeTable(interner: interner)

        for primitive in primitives {
            let type = types.make(.primitive(primitive, .nonNull))
            let box = try loweringBoxingABI(.box, for: primitive, nonNull: true)
            let unbox = try loweringBoxingABI(.unbox, for: primitive, nonNull: true)
            #expect(table.boxCallee(for: type, types: types, requireNonNull: true) == interner.intern(box.name))
            #expect(table.unboxCallee(for: type, types: types, requireNonNull: true) == interner.intern(unbox.name))
        }

        // Nullable Long/ULong/Double must keep the null-aware box variant:
        // their raw bits can collide with the runtime null sentinel.
        for primitive in [PrimitiveType.long, .ulong, .double] {
            let nullableType = types.make(.primitive(primitive, .nullable))
            let box = try loweringBoxingABI(.box, for: primitive)
            #expect(table.boxCallee(for: nullableType, types: types, requireNonNull: false) == interner.intern(box.name))
        }

        let nullableInt = types.make(.primitive(.int, .nullable))
        #expect(table.boxCallee(for: nullableInt, types: types, requireNonNull: true) == nil)
        #expect(table.unboxCallee(for: nullableInt, types: types, requireNonNull: true) == nil)

        let stringType = types.make(.stringStruct(.nonNull))
        let stringBox = try loweringRuntimeABI("string_from_flat")
        let stringUnbox = try loweringRuntimeABI("string_to_flat")
        #expect(table.boxCallee(for: stringType, types: types, requireNonNull: true) == interner.intern(stringBox.name))
        #expect(table.unboxCallee(for: stringType, types: types, requireNonNull: true) == interner.intern(stringUnbox.name))

        let nullableString = types.make(.stringStruct(.nullable))
        #expect(table.boxCallee(for: nullableString, types: types, requireNonNull: true) == nil)
        #expect(table.unboxCallee(for: nullableString, types: types, requireNonNull: true) == nil)
    }

    @Test
    func testStaticPrimitiveLookupUsesTaggedHandleABI() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let table = BoxingCalleeTable(interner: interner)

        for primitive in primitives {
            let type = types.make(.primitive(primitive, .nonNull))
            let box = try loweringBoxingABI(.box, for: primitive, nonNull: true, staticPrimitive: true)
            let unbox = try loweringBoxingABI(.unbox, for: primitive, nonNull: true, staticPrimitive: true)
            #expect(
                table.boxCallee(for: type, types: types, requireNonNull: true, preferStaticPrimitive: true)
                    == interner.intern(box.name)
            )
            #expect(
                table.unboxCallee(for: type, types: types, requireNonNull: true, preferStaticPrimitive: true)
                    == interner.intern(unbox.name)
            )
        }
    }

    @Test(arguments: [false, true])
    func testNullableDoubleUnboxingKeepsNullAwareCallee(preferStaticPrimitive: Bool) throws {
        let interner = StringInterner()
        let table = BoxingCalleeTable(interner: interner)
        let callee = table.unboxCallee(
            for: .primitive(.double, .nullable),
            requireNonNull: false,
            preferStaticPrimitive: preferStaticPrimitive
        )
        let abi = try loweringBoxingABI(.unbox, for: .double, staticPrimitive: preferStaticPrimitive)
        #expect(callee == interner.intern(abi.name))
    }
}
#endif
