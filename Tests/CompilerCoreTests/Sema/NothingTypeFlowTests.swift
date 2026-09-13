#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NothingTypeFlowTests {

    // MARK: - Consolidated Sema tests

    @Test
    func testNothingTypeFlowSema() throws {
        let sources: [String] = [
            // testControlFlowTerminalsBindNothingType
            """
            package sample0

                    class E

                    fun f(flag: Boolean): Int {
                        var x = 0
                        while (x < 5) {
                            x = x + 1
                            if (x == 2) continue
                            if (x == 4) break
                        }
                        if (flag) return x
                        throw E()
                    }

            """,
            // testNothingParticipatesAsBottomInIfWhenTryLUB
            """
            package sample1

                    class E

                    fun ifCase(flag: Boolean): Int {
                        val x: Int = if (flag) 1 else throw E()
                        return x
                    }

                    fun whenCase(flag: Boolean): Int = when (flag) {
                        true -> 1
                        false -> throw E()
                    }

                    fun tryCase(flag: Boolean): Int = try {
                        if (flag) 1 else throw E()
                    } catch (e: E) {
                        2
                    }

            """,
            // testNullLiteralUsesNullableNothingAndLubWithIntBecomesNullableInt
            """
            package sample2

                    fun f(): Int? {
                        val x = null
                        return x
                    }

            """,
            // testUnreachableAfterNothingEmitsDiagnostic
            """
            package sample3

                    class E

                    fun f(): Int {
                        throw E()
                        return 1
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testControlFlowTerminalsBindNothingType ===

            do {

                let sample0Path = paths[0]


                let returnExprs = allExprIDs(in: ast, path: sample0Path, ctx: ctx) { _, expr in
                    if case .returnExpr = expr { return true }
                    return false
                }
                let breakExprs = allExprIDs(in: ast, path: sample0Path, ctx: ctx) { _, expr in
                    if case .breakExpr = expr { return true }
                    return false
                }
                let continueExprs = allExprIDs(in: ast, path: sample0Path, ctx: ctx) { _, expr in
                    if case .continueExpr = expr { return true }
                    return false
                }
                let throwExprs = allExprIDs(in: ast, path: sample0Path, ctx: ctx) { _, expr in
                    if case .throwExpr = expr { return true }
                    return false
                }

                #expect(!returnExprs.isEmpty)
                #expect(!breakExprs.isEmpty)
                #expect(!continueExprs.isEmpty)
                #expect(!throwExprs.isEmpty)

                for exprID in returnExprs + breakExprs + continueExprs + throwExprs {
                    #expect(
                        sema.bindings.exprType(for: exprID) == sema.types.nothingType,
                        "Expected terminal control-flow expression to be typed as Nothing."
                    )
                }

            }

            // === testNothingParticipatesAsBottomInIfWhenTryLUB ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let allIfExprIDs = allExprIDs(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                    guard case .ifExpr = expr else { return false }
                    return true
                }
                let ifExprIDs = allIfExprIDs.filter {
                    sema.bindings.exprType(for: $0) == sema.types.intType
                }
                let whenExprIDs = allExprIDs(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                    guard case .whenExpr = expr else { return false }
                    return true
                }
                let tryExprIDs = allExprIDs(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                    guard case .tryExpr = expr else { return false }
                    return true
                }

                // 2 user if-expressions (ifCase + tryCase), both merged to Int via
                // Nothing-as-bottom LUB.
                #expect(ifExprIDs.count == 2, "Expected 2 user if-expressions typed as Int via Nothing-as-bottom LUB")
                #expect(!whenExprIDs.isEmpty)
                #expect(!tryExprIDs.isEmpty)

                for exprID in ifExprIDs + whenExprIDs + tryExprIDs {
                    #expect(
                        sema.bindings.exprType(for: exprID) == sema.types.intType,
                        "Expected control-flow merge with Nothing branch to infer Int."
                    )
                }

                #expect(!sample1Diagnostics.contains { $0.severity == .error }, "Unexpected diagnostics: \(sample1Diagnostics.map { "\($0.code): \($0.message)" })")

            }

            // === testNullLiteralUsesNullableNothingAndLubWithIntBecomesNullableInt ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let nullNameRef = try #require(firstExprID(in: ast, path: sample2Path, ctx: ctx) { _, expr in
                    guard case let .nameRef(name, _) = expr else { return false }
                    return interner.resolve(name) == "null"
                })
                #expect(sema.bindings.exprType(for: nullNameRef) == sema.types.nullableNothingType)

                let nullableInt = sema.types.makeNullable(sema.types.intType)
                #expect(
                    sema.types.lub([sema.types.intType, sema.types.nullableNothingType]) == nullableInt
                )
                #expect(!sample2Diagnostics.contains { $0.severity == .error })

            }

            // === testUnreachableAfterNothingEmitsDiagnostic ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0096", in: sample3Diagnostics)

            }

        }
    }

}

#endif
