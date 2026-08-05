#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-CAP-013: `resolveTypeRef` used to resolve an unqualified type name
/// (e.g. `Lazy` in `val x: Lazy<Int> = ...`) via a global short-name scan
/// across *all* packages, sorted by internal symbol ID, completely ignoring
/// lexical scope / import priority. Since `kotlin.properties.Lazy` (an
/// unrelated, zero-arity marker interface, not a default import) happens to
/// be registered before `kotlin.Lazy` (the real, one-arity `out T` interface
/// returned by `lazy`/`lazyOf`), the annotation resolved to the wrong symbol
/// and the return-type constraint against the correctly-typed `lazyOf`/`lazy`
/// call always failed with KSWIFTK-TYPE-0001.
@Suite
struct GenericFunctionExpectedTypeConstraintTests {

    /// Unqualified `Lazy` must never resolve to the unrelated
    /// `kotlin.properties.Lazy` marker interface, which is not a default
    /// import and declares no type parameters or `value` member.
    private func assertLocalIsRootKotlinLazy(
        named targetName: String,
        ctx: CompilationContext
    ) throws {
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let interner = ctx.interner

        let rootLazyFQName = ["kotlin", "Lazy"].map { interner.intern($0) }
        let legacyLazyFQName = ["kotlin", "properties", "Lazy"].map { interner.intern($0) }
        let rootLazySymbol = try #require(sema.symbols.lookup(fqName: rootLazyFQName))

        let mainBody = try #require(findMainBodyStatements(in: ast, interner: interner))
        var checked = false
        for exprID in mainBody {
            guard let expr = ast.arena.expr(exprID),
                  case let .localDecl(name, _, _, initializer, _, _) = expr,
                  interner.resolve(name) == targetName,
                  let initializer,
                  let boundType = sema.bindings.exprType(for: initializer)
            else { continue }

            guard case let .classType(classType) = sema.types.kind(of: boundType) else {
                Issue.record("Expected \(targetName) to bind to a class type, got \(sema.types.renderType(boundType))")
                continue
            }
            #expect(classType.classSymbol == rootLazySymbol)
            if let legacyLazySymbol = sema.symbols.lookup(fqName: legacyLazyFQName) {
                #expect(classType.classSymbol != legacyLazySymbol)
            }
            checked = true
        }
        #expect(checked, "Expected to find local declaration named \(targetName)")
    }

    private func findMainBodyStatements(
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID]? {
        for file in ast.files {
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
            // testLazyOfMatchesExplicitLazyExpectedType
            """
            package sample0

                    fun main() {
                        val x: Lazy<Int> = lazyOf(1)
                        println(x.value)
                    }

            """,
            // testLazyBlockMatchesExplicitLazyExpectedType
            """
            package sample1

                    fun main() {
                        val x: Lazy<Int> = lazy { 1 }
                        println(x.value)
                    }

            """,
            // testLazyModeMatchesExplicitLazyExpectedType
            """
            package sample2

                    fun main() {
                        val x: Lazy<Int> = lazy(LazyThreadSafetyMode.NONE) { 1 }
                        println(x.value)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testLazyOfMatchesExplicitLazyExpectedType ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample0Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample0Diagnostics)
                #expect(sample0Diagnostics.isEmpty, "Got: \(sample0Diagnostics)")

                try assertLocalIsRootKotlinLazy(named: "x", ctx: ctx)

            }

            // === testLazyBlockMatchesExplicitLazyExpectedType ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample1Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample1Diagnostics)
                #expect(sample1Diagnostics.isEmpty, "Got: \(sample1Diagnostics)")

                try assertLocalIsRootKotlinLazy(named: "x", ctx: ctx)

            }

            // === testLazyModeMatchesExplicitLazyExpectedType ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample2Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample2Diagnostics)
                #expect(sample2Diagnostics.isEmpty, "Got: \(sample2Diagnostics)")

                try assertLocalIsRootKotlinLazy(named: "x", ctx: ctx)

            }

        }
    }

}

#endif
