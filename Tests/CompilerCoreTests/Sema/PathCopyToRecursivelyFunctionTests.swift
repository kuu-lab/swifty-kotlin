#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-PATH-FN-010: Validates that `kotlin.io.path.Path.copyToRecursively(...)` resolves
/// through Sema for both overload shapes:
///   - `copyToRecursively(target, onError, followLinks, overwrite): Path`  → kk_path_copyToRecursively_overwrite
///   - `copyToRecursively(target, onError, followLinks, copyAction): Path` → kk_path_copyToRecursively_copyAction
///
/// The extension functions are wired through the synthetic Path stub registry in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPathStubs.swift`, and are
/// expected to bind to the runtime helpers declared in
/// `Sources/RuntimeABI/RuntimeABISpec.swift`.
@Suite
struct PathCopyToRecursivelyFunctionTests {

    // MARK: - overwrite overload

    // MARK: - copyAction overload

    // MARK: - both overloads registered

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
            // testPathCopyToRecursivelyOverwriteResolvesWithAllArguments
            """
            package sample0

                    import kotlin.Exception
                    import kotlin.io.path.OnErrorResult
                    import kotlin.io.path.Path
                    import kotlin.io.path.copyToRecursively

                    fun copyTree(source: Path, target: Path, onError: (Path, Path, Exception) -> OnErrorResult): Path {
                        return source.copyToRecursively(target, onError, true, true)
                    }

            """,
            // testPathCopyToRecursivelyOverwriteSignatureAndRuntimeLink
            """
            package sample1
            fun noop() {}
            """,
            // testPathCopyToRecursivelyCopyActionResolvesWithAllArguments
            """
            package sample2

                    import kotlin.Exception
                    import kotlin.io.path.CopyActionContext
                    import kotlin.io.path.CopyActionResult
                    import kotlin.io.path.OnErrorResult
                    import kotlin.io.path.Path
                    import kotlin.io.path.copyToRecursively

                    fun copyTree(
                        source: Path,
                        target: Path,
                        onError: (Path, Path, Exception) -> OnErrorResult,
                        copyAction: CopyActionContext.(Path, Path) -> CopyActionResult
                    ): Path {
                        return source.copyToRecursively(target, onError, true, copyAction)
                    }

            """,
            // testPathCopyToRecursivelyCopyActionSignatureAndRuntimeLink
            """
            package sample3
            fun noop() {}
            """,
            // testBothCopyToRecursivelyOverloadsAreRegistered
            """
            package sample4
            fun noop() {}
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testPathCopyToRecursivelyOverwriteResolvesWithAllArguments ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Path.copyToRecursively(target, onError, followLinks, overwrite) should resolve without errors, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testPathCopyToRecursivelyOverwriteSignatureAndRuntimeLink ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let symbols = sema.symbols
                let types = sema.types

                let pathSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
                )
                let exceptionSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "Exception"].map(interner.intern))
                )
                let onErrorResultSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "io", "path", "OnErrorResult"].map(interner.intern))
                )
                let pathType = types.make(
                    .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
                )
                let exceptionType = types.make(
                    .classType(ClassType(classSymbol: exceptionSymbol, args: [], nullability: .nonNull))
                )
                let onErrorResultType = types.make(
                    .classType(ClassType(classSymbol: onErrorResultSymbol, args: [], nullability: .nonNull))
                )
                let onErrorType = types.make(.functionType(FunctionType(
                    params: [pathType, pathType, exceptionType],
                    returnType: onErrorResultType,
                    isSuspend: false,
                    nullability: .nonNull
                )))

                let candidates = symbols.lookupAll(
                    fqName: ["kotlin", "io", "path", "copyToRecursively"].map(interner.intern)
                )
                let overwriteOverload = try #require(candidates.first { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == pathType
                        && signature.parameterTypes == [pathType, onErrorType, types.booleanType, types.booleanType]
                        && signature.returnType == pathType
                }, "overwrite overload of copyToRecursively must be registered")

                #expect(
                    symbols.externalLinkName(for: overwriteOverload) == "kk_path_copyToRecursively_overwrite",
                    "overwrite overload must bind to kk_path_copyToRecursively_overwrite"
                )

                let signature = try #require(symbols.functionSignature(for: overwriteOverload))
                #expect(signature.receiverType == pathType)
                #expect(signature.returnType == pathType)
                #expect(signature.parameterTypes.count == 4)

            }

            // === testPathCopyToRecursivelyCopyActionResolvesWithAllArguments ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let errors = sample2Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Path.copyToRecursively(target, onError, followLinks, copyAction) should resolve without errors, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testPathCopyToRecursivelyCopyActionSignatureAndRuntimeLink ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let symbols = sema.symbols
                let types = sema.types

                let pathSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
                )
                let exceptionSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "Exception"].map(interner.intern))
                )
                let onErrorResultSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "io", "path", "OnErrorResult"].map(interner.intern))
                )
                let copyActionContextSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "io", "path", "CopyActionContext"].map(interner.intern))
                )
                let copyActionResultSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "io", "path", "CopyActionResult"].map(interner.intern))
                )
                let pathType = types.make(
                    .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
                )
                let exceptionType = types.make(
                    .classType(ClassType(classSymbol: exceptionSymbol, args: [], nullability: .nonNull))
                )
                let onErrorResultType = types.make(
                    .classType(ClassType(classSymbol: onErrorResultSymbol, args: [], nullability: .nonNull))
                )
                let copyActionContextType = types.make(
                    .classType(ClassType(classSymbol: copyActionContextSymbol, args: [], nullability: .nonNull))
                )
                let copyActionResultType = types.make(
                    .classType(ClassType(classSymbol: copyActionResultSymbol, args: [], nullability: .nonNull))
                )
                let onErrorType = types.make(.functionType(FunctionType(
                    params: [pathType, pathType, exceptionType],
                    returnType: onErrorResultType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let copyActionType = types.make(.functionType(FunctionType(
                    receiver: copyActionContextType,
                    params: [pathType, pathType],
                    returnType: copyActionResultType,
                    isSuspend: false,
                    nullability: .nonNull
                )))

                let candidates = symbols.lookupAll(
                    fqName: ["kotlin", "io", "path", "copyToRecursively"].map(interner.intern)
                )
                let copyActionOverload = try #require(candidates.first { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == pathType
                        && signature.parameterTypes == [pathType, onErrorType, types.booleanType, copyActionType]
                        && signature.returnType == pathType
                }, "copyAction overload of copyToRecursively must be registered")

                #expect(
                    symbols.externalLinkName(for: copyActionOverload) == "kk_path_copyToRecursively_copyAction",
                    "copyAction overload must bind to kk_path_copyToRecursively_copyAction"
                )

                let signature = try #require(symbols.functionSignature(for: copyActionOverload))
                #expect(signature.receiverType == pathType)
                #expect(signature.returnType == pathType)
                #expect(signature.parameterTypes.count == 4)

            }

            // === testBothCopyToRecursivelyOverloadsAreRegistered ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let symbols = sema.symbols

                let candidates = symbols.lookupAll(
                    fqName: ["kotlin", "io", "path", "copyToRecursively"].map(interner.intern)
                )
                #expect(
                    candidates.count >= 2,
                    "At least two copyToRecursively overloads (overwrite and copyAction) must be registered"
                )

                let linkNames = Set(candidates.compactMap { symbols.externalLinkName(for: $0) })
                #expect(
                    linkNames.contains("kk_path_copyToRecursively_overwrite"),
                    "overwrite overload must be present"
                )
                #expect(
                    linkNames.contains("kk_path_copyToRecursively_copyAction"),
                    "copyAction overload must be present"
                )

            }

        }
    }

}

#endif
