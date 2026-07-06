#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NothingTypeFlowTests {
    @Test
    func testControlFlowTerminalsBindNothingType() throws {
        let source = """
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
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let returnExprs = exprIDs(in: ast) { expr in
                if case .returnExpr = expr { return true }
                return false
            }
            let breakExprs = exprIDs(in: ast) { expr in
                if case .breakExpr = expr { return true }
                return false
            }
            let continueExprs = exprIDs(in: ast) { expr in
                if case .continueExpr = expr { return true }
                return false
            }
            let throwExprs = exprIDs(in: ast) { expr in
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
    }

    @Test
    func testNothingParticipatesAsBottomInIfWhenTryLUB() throws {
        let source = """
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
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            // Bundled stdlib (padStart/padEnd) also contributes if-expressions
            // typed as String. Filter to user-code if-expressions only by
            // checking against intType (the LUB result for Nothing branches).
            let allIfExprIDs = exprIDs(in: ast) { expr in
                if case .ifExpr = expr { return true }
                return false
            }
            let ifExprIDs = allIfExprIDs.filter {
                sema.bindings.exprType(for: $0) == sema.types.intType
            }
            let whenExprIDs = exprIDs(in: ast) { expr in
                if case .whenExpr = expr { return true }
                return false
            }
            let tryExprIDs = exprIDs(in: ast) { expr in
                if case .tryExpr = expr { return true }
                return false
            }

            // 2 user if-expressions (ifCase + tryCase), plus bundled stdlib if-expressions
            // that also merge to Int -- including the step-sign branches in
            // Sources/CompilerCore/Stdlib/kotlin/ranges/RangeHOF.kt's six count()
            // implementations (MIGRATION-RANGE-002), plus the two Int-typed
            // if-expressions in Sources/CompilerCore/Stdlib/kotlin/comparisons/Comparisons.kt's
            // maxOf(Int, Int)/minOf(Int, Int) overloads (MIGRATION-COMP-002; the Long
            // overloads' if-expressions are typed Long and excluded by the intType filter).
            #expect(ifExprIDs.count == 21, "Expected 2 user if-expressions typed as Int via Nothing-as-bottom LUB, plus bundled stdlib if-expressions")
            #expect(!whenExprIDs.isEmpty)
            #expect(!tryExprIDs.isEmpty)

            for exprID in ifExprIDs + whenExprIDs + tryExprIDs {
                #expect(
                    sema.bindings.exprType(for: exprID) == sema.types.intType,
                    "Expected control-flow merge with Nothing branch to infer Int."
                )
            }

            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })")
        }
    }

    @Test
    func testNullLiteralUsesNullableNothingAndLubWithIntBecomesNullableInt() throws {
        let source = """
        fun f(): Int? {
            val x = null
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let nullNameRef = try #require(firstExprID(in: ast) { _, expr in
                guard case let .nameRef(name, _) = expr else { return false }
                return ctx.interner.resolve(name) == "null"
            })
            #expect(sema.bindings.exprType(for: nullNameRef) == sema.types.nullableNothingType)

            let nullableInt = sema.types.makeNullable(sema.types.intType)
            #expect(
                sema.types.lub([sema.types.intType, sema.types.nullableNothingType]) == nullableInt
            )
            #expect(!ctx.diagnostics.hasError)
        }
    }

    @Test
    func testUnreachableAfterNothingEmitsDiagnostic() throws {
        let source = """
        class E

        fun f(): Int {
            throw E()
            return 1
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0096", in: ctx)
        }
    }

    private func exprIDs(
        in ast: ASTModule,
        where predicate: (Expr) -> Bool
    ) -> [ExprID] {
        var result: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            if predicate(expr) {
                result.append(exprID)
            }
        }
        return result
    }
}
#endif
