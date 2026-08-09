#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-IO-FN-007: Validates that `InputStream.bufferedReader(charset)` —
/// the `kotlin.io` top-level extension on `java.io.InputStream` — resolves
/// through Sema for both the default-charset and explicit-charset call
/// shapes, and that the returned `BufferedReader` exposes its `readLine`,
/// `readLines`, `read`, `ready`, and `close` members so the `.use { }`
/// closeable pattern works.
///
/// Runtime link names involved: `kk_input_stream_bufferedReader`,
/// `kk_buffered_reader_readLine`, `kk_buffered_reader_close`.
@Suite
struct InputStreamBufferedReaderFunctionTests {

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
            // testInputStreamBufferedReaderResolvesWithDefaultCharset
            """
            package sample0

                    import java.io.ByteArrayInputStream
                    import java.io.BufferedReader
                    import java.io.InputStream

                    fun readWithDefaults(bytes: List<Int>): String? {
                        val stream: InputStream = ByteArrayInputStream(bytes)
                        val reader: BufferedReader = stream.bufferedReader()
                        val firstLine = reader.readLine()
                        reader.close()
                        return firstLine
                    }

            """,
            // testInputStreamBufferedReaderResolvesWithExplicitCharset
            """
            package sample1

                    import java.io.ByteArrayInputStream
                    import java.io.BufferedReader
                    import java.io.InputStream
                    import kotlin.text.Charsets

                    fun readAllLines(bytes: List<Int>): List<String> {
                        val stream: InputStream = ByteArrayInputStream(bytes)
                        val reader: BufferedReader = stream.bufferedReader(Charsets.UTF_8)
                        return reader.readLines()
                    }

            """,
            // testInputStreamBufferedReaderSignatureIsExtensionOnInputStream
            """
            package sample2

                    fun probe() {}

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testInputStreamBufferedReaderResolvesWithDefaultCharset ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "InputStream.bufferedReader() with default charset should type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testInputStreamBufferedReaderResolvesWithExplicitCharset ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "InputStream.bufferedReader(Charsets.UTF_8) should type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testInputStreamBufferedReaderSignatureIsExtensionOnInputStream ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let symbols = sema.symbols
                let types = sema.types

                let bufferedReaderName = interner.intern("bufferedReader")
                let kotlinIOFQName: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("io"),
                    bufferedReaderName,
                ]

                let inputStreamFQName: [InternedString] = [
                    interner.intern("java"),
                    interner.intern("io"),
                    interner.intern("InputStream"),
                ]
                let bufferedReaderClassFQName: [InternedString] = [
                    interner.intern("java"),
                    interner.intern("io"),
                    interner.intern("BufferedReader"),
                ]
                guard let inputStreamSymbol = symbols.lookup(fqName: inputStreamFQName) else {
                    Issue.record("InputStream class symbol not registered")
                    return
                }
                guard let bufferedReaderSymbol = symbols.lookup(fqName: bufferedReaderClassFQName) else {
                    Issue.record("BufferedReader class symbol not registered")
                    return
                }

                let inputStreamType = types.make(.classType(ClassType(
                    classSymbol: inputStreamSymbol, args: [], nullability: .nonNull
                )))
                let bufferedReaderType = types.make(.classType(ClassType(
                    classSymbol: bufferedReaderSymbol, args: [], nullability: .nonNull
                )))

                let candidates = symbols.lookupAll(fqName: kotlinIOFQName)
                let matching = candidates.first { symbolID -> Bool in
                    guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == inputStreamType
                        && signature.returnType == bufferedReaderType
                        && signature.parameterTypes.count == 1
                }

                guard let functionSymbol = matching else {
                    Issue.record(
                        "kotlin.io.bufferedReader extension on InputStream not registered (found \(candidates.count) candidate(s))"
                    )
                    return
                }

                #expect(
                    symbols.externalLinkName(for: functionSymbol) == "kk_input_stream_bufferedReader",
                    "InputStream.bufferedReader must link to kk_input_stream_bufferedReader"
                )

                guard let signature = symbols.functionSignature(for: functionSymbol) else {
                    Issue.record("Function signature unavailable")
                    return
                }
                #expect(
                    signature.valueParameterHasDefaultValues == [true],
                    "InputStream.bufferedReader's charset parameter must carry a default value"
                )

            }

        }
    }

}

#endif
