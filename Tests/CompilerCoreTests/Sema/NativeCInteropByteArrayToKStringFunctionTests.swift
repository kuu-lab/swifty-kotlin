#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropByteArrayToKStringFunctionTests {

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
            // testByteArrayToKStringFunctionSurfaceMatchesNativeShape
            """
            package sample0
            fun noop() {}
            """,
            // testByteArrayToKStringFunctionResolvesInSource
            """
            package sample1

                    import kotlinx.cinterop.toKString

                    fun decode(bytes: ByteArray): String {
                        return bytes.toKString()
                    }

            """,
            // testByteArrayToKStringFunctionResolvesWithAllArgs
            """
            package sample2

                    import kotlinx.cinterop.toKString

                    fun decode(bytes: ByteArray): String {
                        return bytes.toKString(0, bytes.size, false)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testByteArrayToKStringFunctionSurfaceMatchesNativeShape ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(!(sample0Diagnostics.contains { $0.severity == .error }), "compile clean: \(sample0Diagnostics)")
                let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
                let kotlinPkg = [interner.intern("kotlin")]

                let byteArraySymbol = try #require(
                    sema.symbols.lookup(fqName: kotlinPkg + [interner.intern("ByteArray")]),
                    "kotlin.ByteArray must be registered"
                )
                let byteArrayType = sema.types.make(.classType(ClassType(
                    classSymbol: byteArraySymbol,
                    args: [],
                    nullability: .nonNull
                )))

                let candidates = sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("toKString")])
                let fn = try #require(candidates.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == byteArrayType
                        && sig.parameterTypes == [sema.types.intType, sema.types.intType, sema.types.booleanType]
                        && sig.returnType == sema.types.stringType
                }, "ByteArray.toKString(startIndex, endIndex, throwOnInvalidSequence) must be registered")
                let flags = try #require(sema.symbols.symbol(fn)?.flags)
                #expect(!flags.contains(.synthetic))

                // Verify all three parameters have default values
                let sig = try #require(sema.symbols.functionSignature(for: fn))
                #expect(sig.valueParameterHasDefaultValues == [true, true, true])

            }

            // === testByteArrayToKStringFunctionResolvesInSource ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(!(sample1Diagnostics.contains { $0.severity == .error }), "resolve with no args: \(sample1Diagnostics)")

            }

            // === testByteArrayToKStringFunctionResolvesWithAllArgs ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                #expect(!(sample2Diagnostics.contains { $0.severity == .error }), "resolve with all args: \(sample2Diagnostics)")

            }

        }
    }

}

#endif
