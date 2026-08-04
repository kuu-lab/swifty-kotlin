#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-FN-015: Validates that `File.copyTo(target, overwrite, bufferSize)`
/// resolves through Sema for the `java.io.File` receiver and produces a `File`.
///
/// The runtime link name exercised here is `kk_file_copyTo`.
///
/// Kotlin signature:
///
///     public fun File.copyTo(
///         target: File,
///         overwrite: Boolean = false,
///         bufferSize: Int = DEFAULT_BUFFER_SIZE
///     ): File
///
/// Declared in the `kotlin.io` package.
@Suite
struct FileCopyToFunctionTests {

    // MARK: - Single-argument overload (defaults for overwrite and bufferSize)

    // MARK: - Two-argument overload (overwrite supplied)

    // MARK: - Three-argument overload (all parameters supplied)

    // MARK: - Named arguments via default values

    // MARK: - Sema surface inspection

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
            // testFileCopyToWithJustTargetResolves
            """
            package sample0

                    import java.io.File
                    import kotlin.io.copyTo

                    fun copy(source: File, dest: File): File = source.copyTo(dest)

            """,
            // testFileCopyToWithOverwriteFlagResolves
            """
            package sample1

                    import java.io.File
                    import kotlin.io.copyTo

                    fun copy(source: File, dest: File): File = source.copyTo(dest, true)

            """,
            // testFileCopyToWithAllArgumentsResolves
            """
            package sample2

                    import java.io.File
                    import kotlin.io.copyTo

                    fun copy(source: File, dest: File): File = source.copyTo(dest, false, 8 * 1024)

            """,
            // testFileCopyToWithNamedBufferSizeResolves
            """
            package sample3

                    import java.io.File
                    import kotlin.io.copyTo

                    fun copy(source: File, dest: File): File =
                        source.copyTo(target = dest, bufferSize = 4096)

            """,
            // testFileCopyToExtensionFunctionSurfaceIsRegistered
            """
            package sample4

                    import java.io.File
                    import kotlin.io.copyTo

                    fun copy(source: File, dest: File): File = source.copyTo(dest, true, 4096)

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testFileCopyToWithJustTargetResolves ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected File.copyTo(target) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testFileCopyToWithOverwriteFlagResolves ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected File.copyTo(target, overwrite) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testFileCopyToWithAllArgumentsResolves ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let errors = sample2Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected File.copyTo(target, overwrite, bufferSize) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testFileCopyToWithNamedBufferSizeResolves ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let errors = sample3Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected File.copyTo with named bufferSize to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testFileCopyToExtensionFunctionSurfaceIsRegistered ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                #expect(
                    !sample4Diagnostics.contains { $0.severity == .error },
                    "File.copyTo extension function in kotlin.io should resolve: \(sample4Diagnostics.map(\.message))"
                )

                let symbols = sema.symbols
                let types = sema.types

                let fileSymbol = try #require(
                    symbols.lookup(fqName: ["java", "io", "File"].map(interner.intern))
                )
                let fileType = types.make(.classType(ClassType(
                    classSymbol: fileSymbol, args: [], nullability: .nonNull
                )))

                let copyToCandidates = symbols.lookupAll(
                    fqName: ["kotlin", "io", "copyTo"].map(interner.intern)
                )
                let copyTo = try #require(copyToCandidates.first { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == fileType
                        && signature.parameterTypes == [fileType, types.booleanType, types.intType]
                        && signature.returnType == fileType
                })

                #expect(
                    symbols.externalLinkName(for: copyTo) == "kk_file_copyTo"
                )

                let signature = try #require(symbols.functionSignature(for: copyTo))
                #expect(signature.valueParameterHasDefaultValues == [false, true, true])
                #expect(signature.valueParameterIsVararg == [false, false, false])

            }

        }
    }

}

#endif
