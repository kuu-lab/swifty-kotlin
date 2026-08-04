#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Sema-surface tests for the `kotlin.io.bufferedWriter` extension function
/// on `java.io.OutputStream` (STDLIB-IO-FN-009).
///
/// Kotlin signature: `public fun OutputStream.bufferedWriter(
///     charset: Charset = Charsets.UTF_8
/// ): BufferedWriter`
@Suite
struct OutputStreamBufferedWriterFunctionTests {

    /// `OutputStream.bufferedWriter(charset)` should resolve to the
    /// synthetic extension function in `kotlin.io` and return a
    /// `java.io.BufferedWriter`.

    /// `OutputStream.bufferedWriter()` with no arguments should resolve via
    /// the `charset` parameter's default value (`Charsets.UTF_8`).

    /// The returned `BufferedWriter` should be usable for `.write`, `.flush`,
    /// and `.close` member calls — confirming the type chain stays intact.

    /// The Sema layer should record the external link name on the symbol so
    /// codegen can resolve it to `kk_output_stream_bufferedWriter` later in
    /// the pipeline.

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
            // testOutputStreamBufferedWriterWithExplicitCharsetResolves
            """
            package sample0

                    import java.io.BufferedWriter
                    import java.io.File
                    import java.io.OutputStream
                    import kotlin.io.bufferedWriter
                    import kotlin.text.Charsets

                    fun openWriter(file: File): BufferedWriter {
                        val stream: OutputStream = file.outputStream()
                        return stream.bufferedWriter(Charsets.UTF_8)
                    }

            """,
            // testOutputStreamBufferedWriterWithDefaultCharsetResolves
            """
            package sample1

                    import java.io.BufferedWriter
                    import java.io.File
                    import java.io.OutputStream
                    import kotlin.io.bufferedWriter

                    fun openWriter(file: File): BufferedWriter {
                        val stream: OutputStream = file.outputStream()
                        return stream.bufferedWriter()
                    }

            """,
            // testOutputStreamBufferedWriterChainedMemberCallsResolve
            """
            package sample2

                    import java.io.File
                    import java.io.OutputStream
                    import kotlin.io.bufferedWriter
                    import kotlin.text.Charsets

                    fun writeAndClose(file: File) {
                        val stream: OutputStream = file.outputStream()
                        val writer = stream.bufferedWriter(Charsets.UTF_8)
                        writer.write("hello")
                        writer.flush()
                        writer.close()
                    }

            """,
            // testOutputStreamBufferedWriterExternalLinkNameIsRegisteredOnSymbol
            """
            package sample3

                    import java.io.BufferedWriter
                    import java.io.OutputStream
                    import kotlin.io.bufferedWriter
                    import kotlin.text.Charsets

                    fun stub(stream: OutputStream): BufferedWriter = stream.bufferedWriter(Charsets.UTF_8)

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testOutputStreamBufferedWriterWithExplicitCharsetResolves ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let diagnostics = sample0Diagnostics.map(\.message)
                #expect(
                    !(sample0Diagnostics.contains { $0.severity == .error }),
                    "OutputStream.bufferedWriter(charset) extension function in kotlin.io should resolve: \(diagnostics)"
                )

                let symbols = sema.symbols
                let types = sema.types

                let outputStreamSymbol = try #require(
                    symbols.lookup(fqName: ["java", "io", "OutputStream"].map(interner.intern))
                )
                let charsetSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern))
                )
                let bufferedWriterSymbol = try #require(
                    symbols.lookup(fqName: ["java", "io", "BufferedWriter"].map(interner.intern))
                )

                let outputStreamType = types.make(.classType(ClassType(
                    classSymbol: outputStreamSymbol, args: [], nullability: .nonNull
                )))
                let charsetType = types.make(.classType(ClassType(
                    classSymbol: charsetSymbol, args: [], nullability: .nonNull
                )))
                let bufferedWriterType = types.make(.classType(ClassType(
                    classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull
                )))

                let bufferedWriterSymbols = symbols.lookupAll(
                    fqName: ["kotlin", "io", "bufferedWriter"].map(interner.intern)
                )
                let bufferedWriter = try #require(bufferedWriterSymbols.first { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == outputStreamType
                        && signature.parameterTypes == [charsetType]
                        && signature.returnType == bufferedWriterType
                })

                #expect(
                    symbols.externalLinkName(for: bufferedWriter) == "kk_output_stream_bufferedWriter"
                )

                let signature = try #require(symbols.functionSignature(for: bufferedWriter))
                #expect(signature.valueParameterHasDefaultValues == [true])
                #expect(signature.valueParameterIsVararg == [false])

            }

            // === testOutputStreamBufferedWriterWithDefaultCharsetResolves ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let diagnostics = sample1Diagnostics.map(\.message)
                #expect(
                    !(sample1Diagnostics.contains { $0.severity == .error }),
                    "OutputStream.bufferedWriter() with default charset should resolve: \(diagnostics)"
                )

            }

            // === testOutputStreamBufferedWriterChainedMemberCallsResolve ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let diagnostics = sample2Diagnostics.map(\.message)
                #expect(
                    !(sample2Diagnostics.contains { $0.severity == .error }),
                    "Chained BufferedWriter member calls after OutputStream.bufferedWriter should resolve: \(diagnostics)"
                )

            }

            // === testOutputStreamBufferedWriterExternalLinkNameIsRegisteredOnSymbol ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let symbols = sema.symbols
                let types = sema.types

                let outputStreamSymbol = try #require(
                    symbols.lookup(fqName: ["java", "io", "OutputStream"].map(interner.intern))
                )
                let charsetSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern))
                )
                let outputStreamType = types.make(.classType(ClassType(
                    classSymbol: outputStreamSymbol, args: [], nullability: .nonNull
                )))
                let charsetType = types.make(.classType(ClassType(
                    classSymbol: charsetSymbol, args: [], nullability: .nonNull
                )))
                let bufferedWriterCandidates = symbols.lookupAll(
                    fqName: ["kotlin", "io", "bufferedWriter"].map(interner.intern)
                )
                let bufferedWriter = try #require(bufferedWriterCandidates.first { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == outputStreamType
                        && signature.parameterTypes == [charsetType]
                })
                #expect(
                    symbols.externalLinkName(for: bufferedWriter) == "kk_output_stream_bufferedWriter"
                )

            }

        }
    }

}

#endif
