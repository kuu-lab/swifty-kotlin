#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-FN-010: Validates that `File.bufferedWriter()` resolves through Sema
/// for the `java.io.File` receiver and produces a `java.io.BufferedWriter`.
///
/// The runtime link name exercised here is `__kk_file_bufferedWriter`.
///
/// Kotlin signature:
///
///     public fun File.bufferedWriter(
///         charset: Charset = Charsets.UTF_8
///     ): BufferedWriter
///
/// Declared as a synthetic member of `java.io.File` (registered via
/// `registerFileMemberFunction` with no-arg parameters; charset support
/// is handled by the runtime which defaults to UTF-8).
@Suite
struct FileBufferedWriterFunctionTests {

    // MARK: - Basic resolution

    // MARK: - Chained member calls

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
            // testFileBufferedWriterNoArgsResolves
            """
            package sample0

                    import java.io.BufferedWriter
                    import java.io.File

                    fun openWriter(file: File): BufferedWriter = file.bufferedWriter()

            """,
            // testFileBufferedWriterReturnTypeIsBufferedWriter
            """
            package sample1

                    import java.io.BufferedWriter
                    import java.io.File

                    fun getWriter(file: File): BufferedWriter {
                        val w: BufferedWriter = file.bufferedWriter()
                        return w
                    }

            """,
            // testFileBufferedWriterChainedWriteFlushCloseResolve
            """
            package sample2

                    import java.io.File

                    fun writeAndClose(file: File) {
                        val writer = file.bufferedWriter()
                        writer.write("hello")
                        writer.newLine()
                        writer.flush()
                        writer.close()
                    }

            """,
            // testFileBufferedWriterInlineChainedCallsResolve
            """
            package sample3

                    import java.io.File

                    fun writeOneLiner(file: File) {
                        file.bufferedWriter().use { it.write("one-liner") }
                    }

            """,
            // testFileBufferedWriterExtensionFunctionSurfaceIsRegistered
            """
            package sample4

                    import java.io.BufferedWriter
                    import java.io.File

                    fun stub(file: File): BufferedWriter = file.bufferedWriter()

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testFileBufferedWriterNoArgsResolves ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected File.bufferedWriter() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testFileBufferedWriterReturnTypeIsBufferedWriter ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected File.bufferedWriter() return type to be BufferedWriter, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testFileBufferedWriterChainedWriteFlushCloseResolve ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let errors = sample2Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected chained BufferedWriter member calls to resolve, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testFileBufferedWriterInlineChainedCallsResolve ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let errors = sample3Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected inline File.bufferedWriter().use { } to resolve, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testFileBufferedWriterExtensionFunctionSurfaceIsRegistered ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                #expect(
                    !sample4Diagnostics.contains { $0.severity == .error },
                    "File.bufferedWriter() should resolve without errors: \(sample4Diagnostics.map(\.message))"
                )

                let symbols = sema.symbols
                let types = sema.types

                let fileSymbol = try #require(
                    symbols.lookup(fqName: ["java", "io", "File"].map(interner.intern))
                )
                let bufferedWriterSymbol = try #require(
                    symbols.lookup(fqName: ["java", "io", "BufferedWriter"].map(interner.intern))
                )
                let fileType = types.make(.classType(ClassType(
                    classSymbol: fileSymbol, args: [], nullability: .nonNull
                )))
                let bufferedWriterType = types.make(.classType(ClassType(
                    classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull
                )))

                // bufferedWriter is registered as java.io.File.bufferedWriter
                let candidates = symbols.lookupAll(
                    fqName: ["java", "io", "File", "bufferedWriter"].map(interner.intern)
                )
                let bufferedWriter = try #require(candidates.first { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == fileType
                        && signature.parameterTypes == []
                        && signature.returnType == bufferedWriterType
                }, "Expected to find java.io.File.bufferedWriter() with receiver=File, params=[], ret=BufferedWriter")

                #expect(
                    symbols.externalLinkName(for: bufferedWriter) == "__kk_file_bufferedWriter"
                )

                let signature = try #require(symbols.functionSignature(for: bufferedWriter))
                #expect(signature.valueParameterHasDefaultValues == [])
                #expect(signature.valueParameterIsVararg == [])

            }

        }
    }

}

#endif
