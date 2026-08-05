#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCPointerToLongFunctionTests {

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
            // testCPointerToLongFunctionSurfaceMatchesNativeShape
            """
            package sample0
            fun noop() {}
            """,
            // testCPointerToLongFunctionLinksToRuntimeSymbol
            """
            package sample1
            fun noop() {}
            """,
            // testCPointerToLongFunctionResolvesInSource
            """
            package sample2

                    import kotlinx.cinterop.ByteVar
                    import kotlinx.cinterop.CPointer
                    import kotlinx.cinterop.toLong

                    fun pointerAsLong(p: CPointer<ByteVar>?): Long {
                        return p.toLong()
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testCPointerToLongFunctionSurfaceMatchesNativeShape ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(!(sample0Diagnostics.contains { $0.severity == .error }), "Expected CPointer<T>?.toLong() surface to compile cleanly, got: \(sample0Diagnostics)")
                let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

                func cinteropSymbol(_ path: [String]) throws -> SymbolID {
                        let found = sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) })
                    return try #require(found, "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered")
                }
                func cinteropSymbol(_ path: String...) throws -> SymbolID {
                    try cinteropSymbol(path)
                }
                func cinteropType(_ path: String...) throws -> TypeID {
                    sema.types.make(.classType(ClassType(
                        classSymbol: try cinteropSymbol(path),
                        args: [],
                        nullability: .nonNull
                    )))
                }

                let cPointedType = try cinteropType("CPointed")
                let cPointerSymbol = try cinteropSymbol("CPointer")
                let toLongFQName = cinteropPkg + [interner.intern("toLong")]
                let toLongCandidates = sema.symbols.lookupAll(fqName: toLongFQName)

                let toLong = try #require(toLongCandidates.first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    guard let receiverType = signature.receiverType,
                          case let .classType(receiverClassType) = sema.types.kind(of: receiverType),
                          receiverClassType.classSymbol == cPointerSymbol,
                          receiverClassType.nullability == .nullable
                    else {
                        return false
                    }
                    return signature.parameterTypes.isEmpty
                        && signature.returnType == sema.types.longType
                        && signature.typeParameterSymbols.count == 1
                })
                let signature = try #require(sema.symbols.functionSignature(for: toLong))
                let typeParameter = try #require(signature.typeParameterSymbols.first)
                let typeParameterType = sema.types.make(.typeParam(TypeParamType(
                    symbol: typeParameter,
                    nullability: .nonNull
                )))
                let expectedReceiverType = sema.types.make(.classType(ClassType(
                    classSymbol: cPointerSymbol,
                    args: [.invariant(typeParameterType)],
                    nullability: .nullable
                )))
                let flags = try #require(sema.symbols.symbol(toLong)?.flags)

                #expect(flags.isSuperset(of: [.synthetic, .inlineFunction]))
                #expect(sema.symbols.parentSymbol(for: toLong) == sema.symbols.lookup(fqName: cinteropPkg))
                #expect(signature.receiverType == expectedReceiverType)
                #expect(signature.returnType == sema.types.longType)
                #expect(signature.typeParameterUpperBoundsList == [[cPointedType]])
                #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [cPointedType])
                #expect(sema.symbols.parentSymbol(for: typeParameter) == toLong)

            }

            // === testCPointerToLongFunctionLinksToRuntimeSymbol ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
                let toLongFQName = cinteropPkg + [interner.intern("toLong")]
                let toLongCandidates = sema.symbols.lookupAll(fqName: toLongFQName)
                let cPointerSymbol = try #require(
                    sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")])
                )
                let toLong = try #require(toLongCandidates.first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                    guard let receiverType = signature.receiverType,
                          case let .classType(cls) = sema.types.kind(of: receiverType),
                          cls.classSymbol == cPointerSymbol,
                          cls.nullability == .nullable
                    else { return false }
                    return signature.parameterTypes.isEmpty && signature.returnType == sema.types.longType
                })
                #expect(sema.symbols.externalLinkName(for: toLong) == "kk_cpointer_toLong", "CPointer<T>?.toLong() must link to kk_cpointer_toLong")

            }

            // === testCPointerToLongFunctionResolvesInSource ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                #expect(!(sample2Diagnostics.contains { $0.severity == .error }), "Expected CPointer<ByteVar>?.toLong() to resolve, got: \(sample2Diagnostics)")

            }

        }
    }

}

#endif
