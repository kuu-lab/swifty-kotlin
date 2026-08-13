#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-PATH-FN-011: Validates that `kotlin.io.path.Path.createSymbolicLinkPointingTo(target, vararg attributes)`
/// resolves through Sema for plain Path receivers and returns a `kotlin.io.path.Path` value.
/// The extension function is wired through the synthetic Path stub registry in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPathStubs.swift`, and is
/// expected to bind to the runtime helper `kk_path_createSymbolicLinkPointingTo_attributes`
/// declared in `Sources/RuntimeABI/RuntimeABISpec.swift`.
@Suite
struct PathCreateSymbolicLinkPointingToFunctionTests {

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
            // testPathCreateSymbolicLinkPointingToResolvesWithTargetOnly
            """
            package sample0

                    import kotlin.io.path.Path
                    import kotlin.io.path.createSymbolicLinkPointingTo

                    fun makeLink(link: Path, target: Path): Path {
                        return link.createSymbolicLinkPointingTo(target)
                    }

            """,
            // testPathCreateSymbolicLinkPointingToResolvesWithVarargAttributes
            """
            package sample1

                    import java.nio.file.attribute.FileAttribute
                    import kotlin.io.path.Path
                    import kotlin.io.path.createSymbolicLinkPointingTo

                    fun makeLink(link: Path, target: Path, attr: FileAttribute<*>): Path {
                        return link.createSymbolicLinkPointingTo(target, attr)
                    }

            """,
            // testPathCreateSymbolicLinkPointingToFunctionSignatureAndRuntimeLink
            """
            package sample2
            fun noop() {}
            """,
            // testPathCreateSymbolicLinkPointingToCallExpressionTypedAsPath
            """
            package sample3

                    import java.nio.file.attribute.FileAttribute
                    import kotlin.io.path.Path
                    import kotlin.io.path.createSymbolicLinkPointingTo

                    fun makeLinks(link: Path, target: Path, attr: FileAttribute<*>): Path {
                        val noAttrs = link.createSymbolicLinkPointingTo(target)
                        val withAttr = link.createSymbolicLinkPointingTo(target, attr)
                        return withAttr
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testPathCreateSymbolicLinkPointingToResolvesWithTargetOnly ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Path.createSymbolicLinkPointingTo(target) should resolve without attributes, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testPathCreateSymbolicLinkPointingToResolvesWithVarargAttributes ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Path.createSymbolicLinkPointingTo(target, attr) should resolve with vararg FileAttribute args, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testPathCreateSymbolicLinkPointingToFunctionSignatureAndRuntimeLink ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let symbols = sema.symbols
                let types = sema.types

                let pathSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
                )
                let fileAttributeSymbol = try #require(
                    symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttribute"].map(interner.intern))
                )
                let pathType = types.make(
                    .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
                )
                let fileAttributeStarType = types.make(
                    .classType(ClassType(classSymbol: fileAttributeSymbol, args: [.star], nullability: .nonNull))
                )

                let candidates = symbols.lookupAll(
                    fqName: ["kotlin", "io", "path", "createSymbolicLinkPointingTo"].map(interner.intern)
                )
                let createSymLink = try #require(candidates.first { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == pathType
                        && signature.parameterTypes == [pathType, fileAttributeStarType]
                        && signature.returnType == pathType
                })

                #expect(
                    symbols.externalLinkName(for: createSymLink) == "kk_path_createSymbolicLinkPointingTo_attributes",
                    "Path.createSymbolicLinkPointingTo should bind to runtime helper kk_path_createSymbolicLinkPointingTo_attributes"
                )

                let signature = try #require(symbols.functionSignature(for: createSymLink))
                #expect(signature.valueParameterIsVararg == [false, true])
                #expect(signature.returnType == pathType)
                #expect(signature.receiverType == pathType)

            }

            // === testPathCreateSymbolicLinkPointingToCallExpressionTypedAsPath ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                #expect(
                    !sample3Diagnostics.contains { $0.severity == .error },
                    "Path.createSymbolicLinkPointingTo() should resolve cleanly: \(sample3Diagnostics.map(\.message))"
                )

                let symbols = sema.symbols
                let types = sema.types
                let pathSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
                )
                let pathType = types.make(
                    .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
                )

                let callExprs = memberCallExprIDsInPath(named: "createSymbolicLinkPointingTo", in: ast, path: sample3Path, ctx: ctx, interner: interner)
                #expect(callExprs.count == 2)
                for callExpr in callExprs {
                    #expect(
                        sema.bindings.exprTypes[callExpr] == pathType,
                        "Each Path.createSymbolicLinkPointingTo() call expression must be typed as kotlin.io.path.Path"
                    )
                }

            }

        }
    }

}

#endif
