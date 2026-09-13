@testable import CompilerCore
import Testing

@Suite
struct UnsignedPrimitiveMemberCallTests {

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
    // MARK: - Consolidated Sema tests

    @Test
    func testUnsignedPrimitiveMemberCallSema() throws {
        let sources: [String] = [
            // testUnsignedMemberCallsInferExpectedTypes
            """
            package sample0

                    fun sample(ub: UByte, us: UShort, ui: UInt, ul: ULong) {
                        ub.and(ub)
                        us.xor(us)
                        ui.shl(1)
                        ul.ushr(1)
                    }

            """,
            // testUnsignedCoercionMemberCallsInferExpectedTypes
            """
            package sample1

                    fun sample(ub: UByte, us: UShort, ui: UInt, ul: ULong) {
                        ub.coerceAtLeast(1u)
                        us.coerceAtMost(2u)
                        ui.coerceIn(1u, 3u)
                        ui.coerceIn(1u..3u)
                        ul.coerceIn(1uL, 3uL)
                        ul.coerceIn(1uL..3uL)
                    }

            """,
            // testUnsignedCoercionMemberCallsAcceptRangeTypedParameters
            """
            package sample2

                    import kotlin.ranges.UIntRange
                    import kotlin.ranges.ULongRange

                    fun sample(ui: UInt, ul: ULong, ur: UIntRange, lr: ULongRange) {
                        ui.coerceIn(ur)
                        ul.coerceIn(lr)
                    }

            """,
            // testUnsignedCoercionMemberCallsRejectScalarRangeArguments
            """
            package sample3

                    fun sample(ui: UInt, ul: ULong) {
                        ui.coerceIn(5u)
                        ul.coerceIn(5uL)
                    }

            """,
            // testUnsignedSafeInvCallsCompile
            """
            package sample4

                    fun sample(ub: UByte?, us: UShort?) {
                        ub?.inv()
                        us?.inv()
                    }

            """,
            // testUnsignedMemberCallsRejectMixedWidths
            """
            package sample5

                    fun sample(ub: UByte, us: UShort) {
                        ub.and(us)
                    }

            """,
            // testUnsignedMemberCallsRejectNullableRhs
            """
            package sample6

                    fun sample(ub: UByte, rhs: UByte?) {
                        ub.and(rhs)
                    }

            """,
            // testUnsignedMemberCallsRejectShiftOnUByte
            """
            package sample7

                    fun sample(ub: UByte) {
                        ub.shl(1)
                    }

            """,
            // testUnsignedMemberCallsRejectShiftOnUShort
            """
            package sample8

                    fun sample(us: UShort) {
                        us.shr(1)
                    }

            """,
            // testUnsignedToCharIsUnresolved (KSP-1533): unsigned types don't
            // extend kotlin.Number and never declared toChar(), so this must
            // stay unresolved. Locks in the audit finding that kk_ulong_to_char
            // (and its UInt/UByte/UShort siblings) was dead lowering code.
            """
            package sample9

                    fun sample(ul: ULong) {
                        ul.toChar()
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // === testUnsignedMemberCallsInferExpectedTypes ===

            do {

                let sample0Path = paths[0]


                let expectedTypes: [String: TypeID] = [
                    "and": sema.types.ubyteType,
                    "xor": sema.types.ushortType,
                    "shl": sema.types.uintType,
                    "ushr": sema.types.ulongType,
                ]

                for (memberName, expectedType) in expectedTypes {
                    let callExpr = try #require(
                        firstExprID(in: ast, path: sample0Path, ctx: ctx) { _, expr in
                            guard case let .memberCall(_, callee, _, _, _) = expr else {
                                return false
                            }
                            return interner.resolve(callee) == memberName
                        },
                        "Expected a call expression for \(memberName)"
                    )
                    #expect(
                        sema.bindings.exprTypes[callExpr] == expectedType,
                        "\(memberName) should infer expected type"
                    )
                }

            }

            // === testUnsignedCoercionMemberCallsInferExpectedTypes ===

            do {

                let sample1Path = paths[1]


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
                        firstExprID(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                            guard case let .memberCall(receiver, callee, _, args, _) = expr else {
                                return false
                            }
                            return interner.resolve(callee) == check.member
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

            // === testUnsignedCoercionMemberCallsAcceptRangeTypedParameters ===

            do {

                let sample2Path = paths[2]


                let uintRangeType = try nominalRangeType(named: "UIntRange", sema: sema, interner: interner)
                let ulongRangeType = try nominalRangeType(named: "ULongRange", sema: sema, interner: interner)

                let checks: [(receiverType: TypeID, argumentType: TypeID)] = [
                    (sema.types.uintType, uintRangeType),
                    (sema.types.ulongType, ulongRangeType),
                ]

                for check in checks {
                    let callExpr = try #require(
                        firstExprID(in: ast, path: sample2Path, ctx: ctx) { _, expr in
                            guard case let .memberCall(receiver, callee, _, args, _) = expr else {
                                return false
                            }
                            return interner.resolve(callee) == "coerceIn"
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

            // === testUnsignedCoercionMemberCallsRejectScalarRangeArguments ===

            do {



                assertDiagnosticCount("KSWIFTK-SEMA-0002", expected: 2, in: ctx)

            }

            // === testUnsignedSafeInvCallsCompile ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                #expect(sample4Diagnostics.isEmpty, "Expected unsigned safe inv calls to compile cleanly, got: \(sample4Diagnostics)")

            }

            // === testUnsignedMemberCallsRejectMixedWidths ===

            do {

                let sample0Path = paths[5]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0024", in: sample0Diagnostics)

            }

            // === testUnsignedMemberCallsRejectNullableRhs ===

            do {

                let sample1Path = paths[6]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0024", in: sample1Diagnostics)

            }

            // === testUnsignedMemberCallsRejectShiftOnUByte ===

            do {

                let sample2Path = paths[7]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0024", in: sample2Diagnostics)

            }

            // === testUnsignedMemberCallsRejectShiftOnUShort ===

            do {

                let sample3Path = paths[8]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0024", in: sample3Diagnostics)

            }

            // === testUnsignedToCharIsUnresolved (KSP-1533) ===

            do {

                let ulongToCharPath = paths[9]

                let ulongToCharDiagnostics = diagnosticsForPath(ulongToCharPath, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ulongToCharDiagnostics)

            }

        }
    }
}
