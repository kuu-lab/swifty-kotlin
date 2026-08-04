#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NothingTypeFlowTests {

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

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    private func allExprIDsInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func memberCallExprIDsInPath(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    private func firstUserObjectLiteralDeclIDInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == path
            else { continue }
            return declID
        }
        return nil
    }

    private func findMainBodyStatementsInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [ExprID]? {
        guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
        for file in ast.files {
            guard file.fileID == fileID else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

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

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

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

            // === testNothingParticipatesAsBottomInIfWhenTryLUB ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let source = sources[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                // Bundled stdlib contributes if/when/try expressions of its own
                // (e.g. String.padStart/padEnd, Files.kt's fileNormalizePath),
                // and that set grows over time. Filter to user-source expressions
                // only so this test doesn't need updating every time bundled
                // stdlib gains or loses a control-flow expression.
                func isUserSource(_ range: SourceRange) -> Bool {
                    !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                }
                let allIfExprIDs = exprIDs(in: ast) { expr in
                    guard case let .ifExpr(_, _, _, range) = expr else { return false }
                    return isUserSource(range)
                }
                let ifExprIDs = allIfExprIDs.filter {
                    sema.bindings.exprType(for: $0) == sema.types.intType
                }
                let whenExprIDs = exprIDs(in: ast) { expr in
                    guard case let .whenExpr(_, _, _, range) = expr else { return false }
                    return isUserSource(range)
                }
                let tryExprIDs = exprIDs(in: ast) { expr in
                    guard case let .tryExpr(_, _, _, range) = expr else { return false }
                    return isUserSource(range)
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

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let nullNameRef = try #require(firstExprIDInPath(in: ast, path: sample2Path, ctx: ctx) { _, expr in
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

        }
    }

    // MARK: - Consolidated runSema error tests

    @Test
    func testRunSemaWithExpectedDiagnostics() throws {

        let sources: [String] = [
            // testUnreachableAfterNothingEmitsDiagnostic
            """
            package sample0

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

            // === testUnreachableAfterNothingEmitsDiagnostic ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0096", in: sample0Diagnostics)

            }

        }
    }

}

#endif
