@testable import CompilerCore
import Testing

@Suite
struct UnsignedPrimitiveMemberCallTests {
    @Test
    func testUnsignedMemberCallsInferExpectedTypes() throws {
        let source = """
        fun sample(ub: UByte, us: UShort, ui: UInt, ul: ULong) {
            ub.and(ub)
            us.xor(us)
            ui.shl(1)
            ul.ushr(1)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let expectedTypes: [String: TypeID] = [
            "and": sema.types.ubyteType,
            "xor": sema.types.ushortType,
            "shl": sema.types.uintType,
            "ushr": sema.types.ulongType,
        ]

        for (memberName, expectedType) in expectedTypes {
            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else {
                        return false
                    }
                    return ctx.interner.resolve(callee) == memberName
                },
                "Expected a call expression for \(memberName)"
            )
            #expect(
                sema.bindings.exprTypes[callExpr] == expectedType,
                "\(memberName) should infer expected type"
            )
        }
    }

    @Test
    func testUnsignedCoercionMemberCallsInferExpectedTypes() throws {
        let source = """
        fun sample(ub: UByte, us: UShort, ui: UInt, ul: ULong) {
            ub.coerceAtLeast(1u)
            us.coerceAtMost(2u)
            ui.coerceIn(1u, 3u)
            ui.coerceIn(1u..3u)
            ul.coerceIn(1uL, 3uL)
            ul.coerceIn(1uL..3uL)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let checks: [(member: String, receiverType: TypeID, argumentCount: Int)] = [
            ("coerceAtLeast", sema.types.ubyteType, 1),
            ("coerceAtMost", sema.types.ushortType, 1),
            ("coerceIn", sema.types.uintType, 2),
            ("coerceIn", sema.types.uintType, 1),
            ("coerceIn", sema.types.ulongType, 2),
            ("coerceIn", sema.types.ulongType, 1),
        ]

        for check in checks {
            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(receiver, callee, _, args, _) = expr else {
                        return false
                    }
                    return ctx.interner.resolve(callee) == check.member
                        && args.count == check.argumentCount
                        && sema.bindings.exprTypes[receiver] == check.receiverType
                },
                "Expected a call expression for \(check.member)"
            )
            #expect(
                sema.bindings.exprTypes[callExpr] == check.receiverType,
                "\(check.member) should infer the unsigned receiver type"
            )
        }
    }

    @Test
    func testUnsignedCoercionMemberCallsAcceptRangeTypedParameters() throws {
        let source = """
        import kotlin.ranges.UIntRange
        import kotlin.ranges.ULongRange

        fun sample(ui: UInt, ul: ULong, ur: UIntRange, lr: ULongRange) {
            ui.coerceIn(ur)
            ul.coerceIn(lr)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let uintRangeType = try nominalRangeType(named: "UIntRange", sema: sema, interner: ctx.interner)
        let ulongRangeType = try nominalRangeType(named: "ULongRange", sema: sema, interner: ctx.interner)

        let checks: [(receiverType: TypeID, argumentType: TypeID)] = [
            (sema.types.uintType, uintRangeType),
            (sema.types.ulongType, ulongRangeType),
        ]

        for check in checks {
            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(receiver, callee, _, args, _) = expr else {
                        return false
                    }
                    return ctx.interner.resolve(callee) == "coerceIn"
                        && args.count == 1
                        && sema.bindings.exprTypes[receiver] == check.receiverType
                },
                "Expected a range-typed coerceIn call"
            )
            guard case let .memberCall(receiver, _, _, args, _) = ast.arena.expr(callExpr) else {
                Issue.record("Expected member call expression")
                continue
            }
            #expect(sema.bindings.exprTypes[receiver] == check.receiverType)
            #expect(sema.bindings.exprTypes[args[0].expr] == check.argumentType)
            #expect(sema.bindings.exprTypes[callExpr] == check.receiverType)
        }
    }

    @Test
    func testUnsignedCoercionMemberCallsRejectScalarRangeArguments() {
        let source = """
        fun sample(ui: UInt, ul: ULong) {
            ui.coerceIn(5u)
            ul.coerceIn(5uL)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        assertDiagnosticCount("KSWIFTK-SEMA-0002", expected: 2, in: ctx)
    }

    @Test
    func testUnsignedMemberCallsRejectMixedWidths() {
        let source = """
        fun sample(ub: UByte, us: UShort) {
            ub.and(us)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test
    func testUnsignedMemberCallsRejectNullableRhs() {
        let source = """
        fun sample(ub: UByte, rhs: UByte?) {
            ub.and(rhs)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test
    func testUnsignedMemberCallsRejectShiftOnUByte() {
        let source = """
        fun sample(ub: UByte) {
            ub.shl(1)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test
    func testUnsignedMemberCallsRejectShiftOnUShort() {
        let source = """
        fun sample(us: UShort) {
            us.shr(1)
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }

    @Test
    func testUnsignedSafeInvCallsCompile() throws {
        let source = """
        fun sample(ub: UByte?, us: UShort?) {
            ub?.inv()
            us?.inv()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.isEmpty, "Expected unsigned safe inv calls to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
    }

    private func nominalRangeType(
        named name: String,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> TypeID {
        let fqName = ["kotlin", "ranges", name].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected synthetic range type \(name)"
        )
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }
        return ctx
    }
}
