#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DeepRecursiveSyntheticStubTests {

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
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
            // testDeepRecursiveSyntheticTypesAndMembersAreRegistered
            """
            package sample0
            fun noop() {}
            """,
            // testDeepRecursiveFunctionResolvesInSource
            """
            package sample1

                    class Node(val next: Node?)

                    fun makeDepth(): DeepRecursiveFunction<Node?, Int> {
                        val depth: DeepRecursiveFunction<Node?, Int> = DeepRecursiveFunction<Node?, Int> {
                            if (it == null) 0 else callRecursive(it.next) + 1
                        }
                        return depth
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testDeepRecursiveSyntheticTypesAndMembersAreRegistered ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let functionFQName = ["kotlin", "DeepRecursiveFunction"].map { interner.intern($0) }
                let scopeFQName = ["kotlin", "DeepRecursiveScope"].map { interner.intern($0) }

                let functionSymbol = try #require(sema.symbols.lookup(fqName: functionFQName))
                let scopeSymbol = try #require(sema.symbols.lookup(fqName: scopeFQName))

                #expect(sema.symbols.symbol(functionSymbol)?.kind == .class)
                #expect(sema.symbols.symbol(scopeSymbol)?.kind == .class)
                #expect(sema.types.nominalTypeParameterSymbols(for: functionSymbol).count == 2)
                #expect(sema.types.nominalTypeParameterSymbols(for: scopeSymbol).count == 2)

                let functionInit = try #require(sema.symbols.lookup(fqName: functionFQName + [interner.intern("<init>")]))
                #expect(sema.symbols.externalLinkName(for: functionInit) == "kk_deep_recursive_function_new")

                let invokeSymbol = try #require(sema.symbols.lookup(fqName: functionFQName + [interner.intern("invoke")]))
                #expect(sema.symbols.externalLinkName(for: invokeSymbol) == "kk_deep_recursive_function_invoke")
                #expect(sema.symbols.symbol(invokeSymbol)?.flags.contains(.operatorFunction) == true)

                let functionCallRecursive = try #require(
                    sema.symbols.lookup(fqName: functionFQName + [interner.intern("callRecursive")])
                )
                #expect(
                    sema.symbols.externalLinkName(for: functionCallRecursive) == "kk_deep_recursive_function_callRecursive"
                )

                let scopeCallRecursive = try #require(
                    sema.symbols.lookup(fqName: scopeFQName + [interner.intern("callRecursive")])
                )
                #expect(
                    sema.symbols.externalLinkName(for: scopeCallRecursive) == "kk_deep_recursive_scope_callRecursive"
                )

            }

            // === testDeepRecursiveFunctionResolvesInSource ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let diagnosticsEmpty = sample1Diagnostics.isEmpty
                #expect(diagnosticsEmpty)

                let constructorCall = try #require(firstExprIDInPath(in: ast, path: sample1Path, ctx: ctx) { exprID, _ in
                    guard let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee else {
                        return false
                    }
                    return sema.symbols.externalLinkName(for: chosen) == "kk_deep_recursive_function_new"
                })
                let constructorCallee = try #require(sema.bindings.callBinding(for: constructorCall)?.chosenCallee)
                #expect(sema.symbols.externalLinkName(for: constructorCallee) == "kk_deep_recursive_function_new")

            }

        }
    }

}

#endif
