#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-PATH-FN-025: Validates that `kotlin.io.path.Path.inputStream(vararg OpenOption)`
/// resolves through Sema for plain Path receivers and yields a `java.io.InputStream` value.
/// The extension function is wired through the synthetic Path stub registry in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPathStubs.swift`, and is
/// expected to bind to the runtime helper `kk_path_inputStream` declared in
/// `Sources/RuntimeABI/RuntimeABISpec.swift`.
@Suite
struct PathInputStreamFunctionTests {

    private func memberCallExprIDs(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name
            else {
                return nil
            }
            return exprID
        }
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
            // testPathInputStreamResolvesWithNoArguments
            """
            package sample0

                    import java.io.InputStream
                    import kotlin.io.path.Path
                    import kotlin.io.path.inputStream

                    fun openSource(path: Path): InputStream {
                        return path.inputStream()
                    }

            """,
            // testPathInputStreamResolvesWithVarargOpenOptions
            """
            package sample1

                    import java.io.InputStream
                    import java.nio.file.OpenOption
                    import kotlin.io.path.Path
                    import kotlin.io.path.inputStream

                    fun openSource(path: Path, first: OpenOption, second: OpenOption): InputStream {
                        return path.inputStream(first, second)
                    }

            """,
            // testPathInputStreamFunctionSignatureAndRuntimeLink
            """
            package sample2
            fun noop() {}
            """,
            // testPathInputStreamCallExpressionTypedAsInputStream
            """
            package sample3

                    import java.io.InputStream
                    import java.nio.file.OpenOption
                    import kotlin.io.path.Path
                    import kotlin.io.path.inputStream

                    fun openSource(path: Path, option: OpenOption): InputStream {
                        val empty = path.inputStream()
                        val single = path.inputStream(option)
                        return single
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testPathInputStreamResolvesWithNoArguments ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Path.inputStream() should resolve without arguments, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testPathInputStreamResolvesWithVarargOpenOptions ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Path.inputStream(option, option) should resolve with vararg OpenOption args, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testPathInputStreamFunctionSignatureAndRuntimeLink ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let symbols = sema.symbols
                let types = sema.types

                let pathSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
                )
                let openOptionSymbol = try #require(
                    symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern))
                )
                let inputStreamSymbol = try #require(
                    symbols.lookup(fqName: ["java", "io", "InputStream"].map(interner.intern))
                )
                let pathType = types.make(
                    .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
                )
                let openOptionType = types.make(
                    .classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull))
                )
                let inputStreamType = types.make(
                    .classType(ClassType(classSymbol: inputStreamSymbol, args: [], nullability: .nonNull))
                )

                let candidates = symbols.lookupAll(
                    fqName: ["kotlin", "io", "path", "inputStream"].map(interner.intern)
                )
                let inputStream = try #require(candidates.first { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == pathType
                        && signature.parameterTypes == [openOptionType]
                        && signature.returnType == inputStreamType
                })

                #expect(
                    symbols.externalLinkName(for: inputStream) == "kk_path_inputStream",
                    "Path.inputStream should bind to runtime helper kk_path_inputStream"
                )

                let signature = try #require(symbols.functionSignature(for: inputStream))
                #expect(signature.valueParameterIsVararg == [true])
                #expect(signature.valueParameterHasDefaultValues == [false])
                #expect(signature.returnType == inputStreamType)
                #expect(signature.receiverType == pathType)

            }

            // === testPathInputStreamCallExpressionTypedAsInputStream ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                #expect(
                    !sample3Diagnostics.contains { $0.severity == .error },
                    "Path.inputStream() should resolve cleanly: \(sample3Diagnostics.map(\.message))"
                )

                let symbols = sema.symbols
                let types = sema.types
                let inputStreamSymbol = try #require(
                    symbols.lookup(fqName: ["java", "io", "InputStream"].map(interner.intern))
                )
                let inputStreamType = types.make(
                    .classType(ClassType(classSymbol: inputStreamSymbol, args: [], nullability: .nonNull))
                )

                let callExprs = memberCallExprIDsInPath(named: "inputStream", in: ast, path: sample3Path, ctx: ctx, interner: interner)
                #expect(callExprs.count == 2)
                for callExpr in callExprs {
                    #expect(
                        sema.bindings.exprTypes[callExpr] == inputStreamType,
                        "Each Path.inputStream() call expression must be typed as java.io.InputStream"
                    )
                }

            }

        }
    }

}

#endif
