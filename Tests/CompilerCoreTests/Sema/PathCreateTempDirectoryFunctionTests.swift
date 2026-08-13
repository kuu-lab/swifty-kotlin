#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-PATH-FN-012: Validates that the top-level `kotlin.io.path.createTempDirectory`
/// functions resolve through Sema and yield a `kotlin.io.path.Path` return value.
///
/// Two overloads are covered:
/// - `createTempDirectory(directory: Path?, prefix: String?, vararg attributes: FileAttribute<*>): Path`
/// - `createTempDirectory(prefix: String?, vararg attributes: FileAttribute<*>): Path`
///
/// Both are registered in
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticPathStubs.swift`
/// and bound to the runtime helpers declared in `Sources/RuntimeABI/RuntimeABISpec.swift`.
@Suite
struct PathCreateTempDirectoryFunctionTests {

    private func topLevelCallExprIDs(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .call(callee, _, _, range) = expr,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            // Callee is a name expression whose text is the function name.
            if case let .nameRef(text, _) = ast.arena.expr(callee),
               interner.resolve(text) == name {
                return exprID
            }
            return nil
        }
    }

    // MARK: - createTempDirectory(prefix, attributes) overload

    // MARK: - createTempDirectory(directory, prefix, attributes) overload

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
            // testCreateTempDirectoryPrefixAttributesResolvesWithPrefixOnly
            """
            package sample0

                    import kotlin.io.path.Path
                    import kotlin.io.path.createTempDirectory

                    fun makeTempDir(): Path {
                        return createTempDirectory("kswiftk-test-")
                    }

            """,
            // testCreateTempDirectoryPrefixAttributesResolvesWithDefaultPrefix
            """
            package sample1

                    import kotlin.io.path.Path
                    import kotlin.io.path.createTempDirectory

                    fun makeTempDir(): Path {
                        return createTempDirectory()
                    }

            """,
            // testCreateTempDirectoryPrefixAttributesFunctionSignatureAndRuntimeLink
            """
            package sample2
            fun noop() {}
            """,
            // testCreateTempDirectoryPrefixCallExpressionTypedAsPath
            """
            package sample3

                    import kotlin.io.path.Path
                    import kotlin.io.path.createTempDirectory

                    fun makeTempDir(): Path {
                        val a = createTempDirectory("kswiftk-")
                        val b = createTempDirectory()
                        return a
                    }

            """,
            // testCreateTempDirectoryDirectoryPrefixAttributesResolvesWithDirectory
            """
            package sample4

                    import java.nio.file.attribute.FileAttribute
                    import kotlin.io.path.Path
                    import kotlin.io.path.createTempDirectory

                    fun makeTempDir(baseDir: Path, attr: FileAttribute<*>): Path {
                        return createTempDirectory(baseDir, "kswiftk-test-", attr)
                    }

            """,
            // testCreateTempDirectoryDirectoryPrefixAttributesFunctionSignatureAndRuntimeLink
            """
            package sample5
            fun noop() {}
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testCreateTempDirectoryPrefixAttributesResolvesWithPrefixOnly ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(
                    !sample0Diagnostics.contains { $0.severity == .error },
                    Comment(rawValue: "createTempDirectory(prefix) should resolve without errors: "
                        + sample0Diagnostics.filter { $0.severity == .error }.map(\.message).joined(separator: ", "))
                )

            }

            // === testCreateTempDirectoryPrefixAttributesResolvesWithDefaultPrefix ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(
                    !sample1Diagnostics.contains { $0.severity == .error },
                    Comment(rawValue: "createTempDirectory() with default prefix should resolve without errors: "
                        + sample1Diagnostics.filter { $0.severity == .error }.map(\.message).joined(separator: ", "))
                )

            }

            // === testCreateTempDirectoryPrefixAttributesFunctionSignatureAndRuntimeLink ===

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
                let nullableStringType = types.makeNullable(types.stringType)
                let fileAttributeStarType = types.make(
                    .classType(ClassType(classSymbol: fileAttributeSymbol, args: [.star], nullability: .nonNull))
                )

                let candidates = symbols.lookupAll(
                    fqName: ["kotlin", "io", "path", "createTempDirectory"].map(interner.intern)
                )
                let createTempDir = try #require(candidates.first { symbolID in
                    guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == nil
                        && sig.parameterTypes == [nullableStringType, fileAttributeStarType]
                        && sig.returnType == pathType
                }, "Expected to find createTempDirectory(prefix, attributes) overload")

                #expect(
                    symbols.externalLinkName(for: createTempDir) == "kk_path_createTempDirectory_prefix_attributes",
                    "createTempDirectory(prefix, attributes) must bind to kk_path_createTempDirectory_prefix_attributes"
                )
                let signature = try #require(symbols.functionSignature(for: createTempDir))
                #expect(signature.valueParameterHasDefaultValues == [true, false])
                #expect(signature.valueParameterIsVararg == [false, true])
                #expect(signature.returnType == pathType)
                #expect(signature.receiverType == nil)

            }

            // === testCreateTempDirectoryPrefixCallExpressionTypedAsPath ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                #expect(
                    !sample3Diagnostics.contains { $0.severity == .error },
                    Comment(rawValue: "createTempDirectory calls should resolve without errors: "
                        + sample3Diagnostics.map(\.message).joined(separator: ", "))
                )

                let symbols = sema.symbols
                let types = sema.types

                let pathSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
                )
                let pathType = types.make(
                    .classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull))
                )
                let callExprs = topLevelCallExprIDs(named: "createTempDirectory", in: ast, path: sample3Path, ctx: ctx, interner: interner)
                #expect(callExprs.count == 2, "Expected 2 createTempDirectory call expressions")
                for callExpr in callExprs {
                    #expect(
                        sema.bindings.exprTypes[callExpr] == pathType,
                        "Each createTempDirectory() call expression must be typed as kotlin.io.path.Path"
                    )
                }

            }

            // === testCreateTempDirectoryDirectoryPrefixAttributesResolvesWithDirectory ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                #expect(
                    !sample4Diagnostics.contains { $0.severity == .error },
                    Comment(rawValue: "createTempDirectory(directory, prefix, attributes) should resolve without errors: "
                        + sample4Diagnostics.filter { $0.severity == .error }.map(\.message).joined(separator: ", "))
                )

            }

            // === testCreateTempDirectoryDirectoryPrefixAttributesFunctionSignatureAndRuntimeLink ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

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
                let nullablePathType = types.makeNullable(pathType)
                let nullableStringType = types.makeNullable(types.stringType)
                let fileAttributeStarType = types.make(
                    .classType(ClassType(classSymbol: fileAttributeSymbol, args: [.star], nullability: .nonNull))
                )

                let candidates = symbols.lookupAll(
                    fqName: ["kotlin", "io", "path", "createTempDirectory"].map(interner.intern)
                )
                let createTempDir = try #require(candidates.first { symbolID in
                    guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == nil
                        && sig.parameterTypes == [nullablePathType, nullableStringType, fileAttributeStarType]
                        && sig.returnType == pathType
                }, "Expected to find createTempDirectory(directory, prefix, attributes) overload")

                #expect(
                    symbols.externalLinkName(for: createTempDir) == "kk_path_createTempDirectory_directory_prefix_attributes",
                    "createTempDirectory(directory, prefix, attributes) must bind to kk_path_createTempDirectory_directory_prefix_attributes"
                )
                let signature = try #require(symbols.functionSignature(for: createTempDir))
                #expect(signature.valueParameterHasDefaultValues == [false, true, false])
                #expect(signature.valueParameterIsVararg == [false, false, true])
                #expect(signature.returnType == pathType)
                #expect(signature.receiverType == nil)

            }

        }
    }

}

#endif
