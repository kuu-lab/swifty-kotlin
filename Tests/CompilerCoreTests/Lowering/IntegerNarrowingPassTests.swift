#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct IntegerNarrowingPassTests {
    private static nonisolated(unsafe) let sharedSema: SemaModule = makeSemaModule().ctx

    // MARK: - Arithmetic narrowing

    @Test
    func testIntAdditionResultIsNarrowed() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = Self.sharedSema
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let lhs = arena.appendExpr(.temporary(0), type: intType)
        let rhs = arena.appendExpr(.temporary(1), type: intType)
        let result = arena.appendExpr(.temporary(2), type: intType)
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [lhs, rhs], result: result, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        #expect(IntegerNarrowingPass().shouldRun(module: module, ctx: ctx))
        try IntegerNarrowingPass().run(module: module, ctx: ctx)

        let lowered = bodyInDecl(declID, module: module)
        // Expect: kk_op_add -> temp, then kk_int_narrow(temp) -> result.
        guard case let .call(_, addCallee, _, addResult, _, _, _, _) = lowered[0] else {
            Issue.record("Expected arithmetic call to be preserved"); return
        }
        #expect(interner.resolve(addCallee) == "kk_op_add")
        #expect(addResult != result, "Arithmetic result should be redirected to a temporary")

        guard case let .call(_, narrowCallee, narrowArgs, narrowResult, _, _, _, _) = lowered[1] else {
            Issue.record("Expected a narrowing call after the arithmetic call"); return
        }
        #expect(interner.resolve(narrowCallee) == "kk_int_narrow")
        #expect(narrowArgs == [addResult])
        #expect(narrowResult == result, "Narrowing must write back to the original result id")
    }

    @Test
    func testLongAdditionResultIsNotNarrowed() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = Self.sharedSema
        let longType = sema.types.make(.primitive(.long, .nonNull))

        let lhs = arena.appendExpr(.temporary(0), type: longType)
        let rhs = arena.appendExpr(.temporary(1), type: longType)
        let result = arena.appendExpr(.temporary(2), type: longType)
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [lhs, rhs], result: result, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        try IntegerNarrowingPass().run(module: module, ctx: ctx)

        let lowered = bodyInDecl(declID, module: module)
        let narrowCount = lowered.filter { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return interner.resolve(callee) == "kk_int_narrow"
            }
            return false
        }.count
        #expect(narrowCount == 0, "Long arithmetic must not be narrowed to 32 bits")
        guard case let .call(_, addCallee, _, addResult, _, _, _, _) = lowered[0] else {
            Issue.record("Expected the long add call to be preserved"); return
        }
        #expect(interner.resolve(addCallee) == "kk_op_add")
        #expect(addResult == result)
    }

    // MARK: - Char / small-width arithmetic

    @Test(arguments: ["kk_op_add", "kk_op_sub"])
    func testCharPlusMinusIntResultIsWrappedToSixteenBits(calleeName: String) throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = Self.sharedSema

        let lhs = arena.appendExpr(.temporary(0), type: sema.types.charType)
        let rhs = arena.appendExpr(.temporary(1), type: sema.types.intType)
        let result = arena.appendExpr(.temporary(2), type: sema.types.charType)
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern(calleeName), arguments: [lhs, rhs], result: result, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        try IntegerNarrowingPass().run(module: module, ctx: ctx)

        let lowered = bodyInDecl(declID, module: module)
        guard case let .call(_, arithCallee, _, rawResult, _, _, _, _) = lowered[0] else {
            Issue.record("Expected the Char arithmetic call to be preserved"); return
        }
        #expect(interner.resolve(arithCallee) == calleeName)
        #expect(rawResult != result)
        guard case let .call(_, wrapCallee, wrapArgs, wrapResult, _, _, _, _) = lowered[1] else {
            Issue.record("Expected kk_int_to_char after Char arithmetic"); return
        }
        #expect(interner.resolve(wrapCallee) == "kk_int_to_char")
        #expect(wrapArgs == [rawResult])
        #expect(wrapResult == result)
    }

    @Test(arguments: [PrimitiveType.ubyte, .ushort])
    func testSmallUnsignedAdditionResultIsWrappedToUInt(operandKind: PrimitiveType) throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = Self.sharedSema
        let operandType = sema.types.make(.primitive(operandKind, .nonNull))

        let lhs = arena.appendExpr(.temporary(0), type: operandType)
        let rhs = arena.appendExpr(.temporary(1), type: operandType)
        let result = arena.appendExpr(.temporary(2), type: sema.types.uintType)
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [lhs, rhs], result: result, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        try IntegerNarrowingPass().run(module: module, ctx: ctx)

        let lowered = bodyInDecl(declID, module: module)
        #expect(lowered.count == 3)
        guard case let .call(_, addCallee, _, addResult, _, _, _, _) = lowered[0] else {
            Issue.record("Expected the small unsigned add call to be preserved"); return
        }
        #expect(interner.resolve(addCallee) == "kk_op_add")
        #expect(addResult != result)
        guard case let .call(_, narrowCallee, narrowArgs, narrowResult, _, _, _, _) = lowered[1] else {
            Issue.record("Expected UInt narrowing after small unsigned arithmetic"); return
        }
        #expect(interner.resolve(narrowCallee) == "kk_uint_narrow")
        #expect(narrowArgs == [addResult])
        #expect(narrowResult == result)
    }

    // MARK: - Shift rewriting

    @Test
    func testIntShiftLeftIsRewrittenToWidthAwareVariant() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = Self.sharedSema
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let value = arena.appendExpr(.temporary(0), type: intType)
        let distance = arena.appendExpr(.temporary(1), type: intType)
        let result = arena.appendExpr(.temporary(2), type: intType)
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_op_shl"), arguments: [value, distance], result: result, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        try IntegerNarrowingPass().run(module: module, ctx: ctx)

        let lowered = bodyInDecl(declID, module: module)
        guard case let .call(_, callee, args, shiftResult, _, _, _, _) = lowered[0] else {
            Issue.record("Expected the shift call to be present"); return
        }
        #expect(interner.resolve(callee) == "kk_op_ishl", "Int shl must use the 32-bit-aware variant")
        #expect(args == [value, distance], "Shift operands must be preserved")
        #expect(shiftResult == result, "Shift result id must be preserved (rename only)")
    }

    @Test
    func testLongShiftLeftUsesSixBitMaskedVariantWithoutNarrowing() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = Self.sharedSema
        let longType = sema.types.make(.primitive(.long, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let value = arena.appendExpr(.temporary(0), type: longType)
        let distance = arena.appendExpr(.temporary(1), type: intType)
        let result = arena.appendExpr(.temporary(2), type: longType)
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_op_shl"), arguments: [value, distance], result: result, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        try IntegerNarrowingPass().run(module: module, ctx: ctx)

        let lowered = bodyInDecl(declID, module: module)
        guard case let .call(_, callee, args, shiftResult, _, _, _, _) = lowered[0] else {
            Issue.record("Expected the shift call to be present"); return
        }
        // Long shl uses the 64-bit variant (masks the distance to 6 bits) so
        // distances >= 64 are well defined, but the result is NOT narrowed to 32 bits.
        #expect(interner.resolve(callee) == "kk_op_lshl", "Long shl must use the 64-bit-aware variant")
        #expect(args == [value, distance])
        #expect(shiftResult == result)
        let narrowCount = lowered.filter { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                return interner.resolve(callee) == "kk_int_narrow"
            }
            return false
        }.count
        #expect(narrowCount == 0, "Long shift result must not be narrowed to 32 bits")
    }

    @Test(arguments: [("kk_op_shl", "kk_op_ishl"), ("kk_op_shr", "kk_op_iushr")])
    func testUIntShiftUsesFiveBitMaskedLogicalVariantThenUIntNarrow(shift: (String, String)) throws {
        // Kotlin `UInt.shr` is logical and masks the distance to 5 bits
        // (`0xFFFFFFFFu shl 4 == 4294967280u`, `1u shl 32 == 1u`).
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = Self.sharedSema
        let uintType = sema.types.make(.primitive(.uint, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let value = arena.appendExpr(.temporary(0), type: uintType)
        let distance = arena.appendExpr(.temporary(1), type: intType)
        let result = arena.appendExpr(.temporary(2), type: uintType)
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern(shift.0), arguments: [value, distance], result: result, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        try IntegerNarrowingPass().run(module: module, ctx: ctx)

        let lowered = bodyInDecl(declID, module: module)
        guard case let .call(_, callee, args, shiftResult, _, _, _, _) = lowered[0] else {
            Issue.record("Expected the shift call to be present"); return
        }
        #expect(interner.resolve(callee) == shift.1)
        #expect(args == [value, distance])
        #expect(shiftResult != result, "Shift result should be redirected to a temporary")
        guard case let .call(_, narrowCallee, narrowArgs, narrowResult, _, _, _, _) = lowered[1] else {
            Issue.record("Expected kk_uint_narrow after the UInt shift"); return
        }
        #expect(interner.resolve(narrowCallee) == "kk_uint_narrow")
        #expect(narrowArgs == [shiftResult])
        #expect(narrowResult == result)
    }

    @Test(arguments: [("kk_op_shl", "kk_op_lshl"), ("kk_op_shr", "kk_op_lushr")])
    func testULongShiftUsesSixBitMaskedLogicalVariant(shift: (String, String)) throws {
        // Kotlin `ULong.shr` is logical (`ULong.MAX_VALUE shr 1 == Long.MAX_VALUE`).
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = Self.sharedSema
        let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let value = arena.appendExpr(.temporary(0), type: ulongType)
        let distance = arena.appendExpr(.temporary(1), type: intType)
        let result = arena.appendExpr(.temporary(2), type: ulongType)
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern(shift.0), arguments: [value, distance], result: result, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        try IntegerNarrowingPass().run(module: module, ctx: ctx)

        let lowered = bodyInDecl(declID, module: module)
        #expect(lowered.count == 2, "ULong shifts are renamed only, never narrowed")
        guard case let .call(_, callee, args, shiftResult, _, _, _, _) = lowered[0] else {
            Issue.record("Expected the shift call to be present"); return
        }
        #expect(interner.resolve(callee) == shift.1)
        #expect(args == [value, distance])
        #expect(shiftResult == result)
    }

    @Test
    func testUIntAdditionResultIsNarrowedToUInt() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = Self.sharedSema
        let uintType = sema.types.make(.primitive(.uint, .nonNull))

        let lhs = arena.appendExpr(.temporary(0), type: uintType)
        let rhs = arena.appendExpr(.temporary(1), type: uintType)
        let result = arena.appendExpr(.temporary(2), type: uintType)
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [lhs, rhs], result: result, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        #expect(IntegerNarrowingPass().shouldRun(module: module, ctx: ctx))
        try IntegerNarrowingPass().run(module: module, ctx: ctx)

        let lowered = bodyInDecl(declID, module: module)
        guard case let .call(_, addCallee, _, addResult, _, _, _, _) = lowered[0] else {
            Issue.record("Expected arithmetic call to be preserved"); return
        }
        #expect(interner.resolve(addCallee) == "kk_op_add")
        #expect(addResult != result, "Arithmetic result should be redirected to a temporary")

        guard case let .call(_, narrowCallee, narrowArgs, narrowResult, _, _, _, _) = lowered[1] else {
            Issue.record("Expected a narrowing call after the arithmetic call"); return
        }
        #expect(interner.resolve(narrowCallee) == "kk_uint_narrow")
        #expect(narrowArgs == [addResult])
        #expect(narrowResult == result, "Narrowing must write back to the original result id")
    }

    @Test
    func testULongAdditionResultIsNotNarrowed() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = Self.sharedSema
        let ulongType = sema.types.make(.primitive(.ulong, .nonNull))

        let lhs = arena.appendExpr(.temporary(0), type: ulongType)
        let rhs = arena.appendExpr(.temporary(1), type: ulongType)
        let result = arena.appendExpr(.temporary(2), type: ulongType)
        let (module, declID) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [lhs, rhs], result: result, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)

        try IntegerNarrowingPass().run(module: module, ctx: ctx)

        let lowered = bodyInDecl(declID, module: module)
        let narrowCount = lowered.filter { instruction in
            if case let .call(_, callee, _, _, _, _, _, _) = instruction {
                let name = interner.resolve(callee)
                return name == "kk_int_narrow" || name == "kk_uint_narrow"
            }
            return false
        }.count
        #expect(narrowCount == 0, "ULong arithmetic must not be narrowed to 32 or 64 bits")
        guard case let .call(_, addCallee, _, addResult, _, _, _, _) = lowered[0] else {
            Issue.record("Expected the ulong add call to be preserved"); return
        }
        #expect(interner.resolve(addCallee) == "kk_op_add")
        #expect(addResult == result)
    }

    // MARK: - shouldRun

    @Test
    func testShouldRunReturnsFalseWithoutRelevantCallees() {
        let interner = StringInterner()
        let arena = KIRArena()
        let sema = Self.sharedSema
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let (module, _) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("__kk_print_raw"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: sema)
        #expect(!IntegerNarrowingPass().shouldRun(module: module, ctx: ctx))
    }

    @Test
    func testShouldRunReturnsFalseWithoutSema() {
        let interner = StringInterner()
        let arena = KIRArena()
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let v2 = arena.appendExpr(.temporary(2))
        let (module, _) = makeModule(
            body: [
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [v0, v1], result: v2, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            interner: interner,
            arena: arena
        )
        let ctx = makeKIRContext(interner: interner, sema: nil)
        #expect(!IntegerNarrowingPass().shouldRun(module: module, ctx: ctx), "Pass requires sema type info")
    }
}
#endif
