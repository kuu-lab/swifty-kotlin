#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropUsePinnedFunctionTests {

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
            // testUsePinnedFunctionSurfaceMatchesNativeShape
            """
            package sample0
            fun noop() {}
            """,
            // testUsePinnedFunctionResolvesInSource
            """
            package sample1

                    import kotlinx.cinterop.Pinned
                    import kotlinx.cinterop.usePinned

                    fun lengthOfPinned(value: String): Int {
                        return value.usePinned { pinned: Pinned<String> ->
                            pinned.get().length
                        }
                    }

            """,
            // testUsePinnedFunctionPropagatesReceiverToUnpin
            """
            package sample2

                    import kotlinx.cinterop.Pinned
                    import kotlinx.cinterop.usePinned

                    class Box(var value: Int)

                    fun readBoxed(box: Box): Int {
                        return box.usePinned { pinned: Pinned<Box> ->
                            val unwrapped = pinned.get()
                            unwrapped.value
                        }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testUsePinnedFunctionSurfaceMatchesNativeShape ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(!(
                    sample0Diagnostics.contains { $0.severity == .error }
                ), "Expected usePinned surface to compile cleanly, got: \(sample0Diagnostics)")
                let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

                func cinteropSymbol(_ path: [String]) throws -> SymbolID {
                    let found = sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) })
                    return try #require(found, "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered")
                }

                let pinnedSymbol = try cinteropSymbol(["Pinned"])
                let usePinnedSymbol = try cinteropSymbol(["usePinned"])
                let signature = try #require(sema.symbols.functionSignature(for: usePinnedSymbol))

                #expect(signature.typeParameterSymbols.count == 2)
                let tSymbol = try #require(signature.typeParameterSymbols.first)
                let rSymbol = try #require(signature.typeParameterSymbols.last)
                #expect(sema.symbols.symbol(tSymbol)?.name == interner.intern("T"))
                #expect(sema.symbols.symbol(rSymbol)?.name == interner.intern("R"))

                let tType = sema.types.make(.typeParam(TypeParamType(symbol: tSymbol, nullability: .nonNull)))
                let rType = sema.types.make(.typeParam(TypeParamType(symbol: rSymbol, nullability: .nonNull)))
                let expectedBlockParameterType = sema.types.make(.classType(ClassType(
                    classSymbol: pinnedSymbol,
                    args: [.invariant(tType)],
                    nullability: .nonNull
                )))
                let expectedBlockType = sema.types.make(.functionType(FunctionType(
                    params: [expectedBlockParameterType],
                    returnType: rType
                )))

                let flags = try #require(sema.symbols.symbol(usePinnedSymbol)?.flags)
                #expect(flags.isSuperset(of: [.synthetic, .inlineFunction]))
                #expect(signature.receiverType == tType)
                #expect(signature.parameterTypes == [expectedBlockType])
                #expect(signature.returnType == rType)
                #expect(signature.typeParameterUpperBoundsList == [[sema.types.anyType], []])
                #expect(sema.symbols.typeParameterUpperBounds(for: tSymbol) == [sema.types.anyType])
                #expect(sema.symbols.parentSymbol(for: usePinnedSymbol) == sema.symbols.lookup(fqName: cinteropPkg))

            }

            // === testUsePinnedFunctionResolvesInSource ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(!(
                    sample1Diagnostics.contains { $0.severity == .error }
                ), "Expected usePinned to resolve, got: \(sample1Diagnostics)")

            }

            // === testUsePinnedFunctionPropagatesReceiverToUnpin ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                // Regression guard for the try/finally lowering shape (STDLIB-CINTEROP-FN-042):
                // the block result becomes the call result, and no error should be raised even
                // when the block itself contains control flow (a local val + expression body).
                #expect(!(
                    sample2Diagnostics.contains { $0.severity == .error }
                ), "Expected usePinned with a multi-statement block to resolve, got: \(sample2Diagnostics)")

            }

        }
    }

}

#endif
