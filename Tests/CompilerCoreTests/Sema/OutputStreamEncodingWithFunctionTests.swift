#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Sema-surface tests for the `kotlin.io.encoding.encodingWith` extension
/// function on `java.io.OutputStream` (STDLIB-IO-ENC-FN-002).
///
/// Kotlin signature: `public fun OutputStream.encodingWith(
///     base64: Base64
/// ): OutputStream`
@Suite
struct OutputStreamEncodingWithFunctionTests {

    /// `OutputStream.encodingWith(base64)` should resolve to the synthetic
    /// extension function in `kotlin.io.encoding` and return an `OutputStream`.

    /// `encodingWith` should accept each predefined `Base64` variant
    /// (Default / UrlSafe / Mime / Pem) without diagnostics.

    /// The returned `OutputStream` should remain usable for the standard
    /// member calls (`write`, `flush`, `close`) — confirming the type chain
    /// after `encodingWith` is preserved as `OutputStream`.

    /// `encodingWith` itself is a regular Kotlin function (with a body that
    /// delegates to a private external wrapper) — the external link name
    /// lives on that private wrapper, not on `encodingWith`'s own symbol.
    /// Sema should still record it so codegen can resolve the runtime bridge.

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
            // testOutputStreamEncodingWithResolves
            """
            package sample0

                    import java.io.File
                    import java.io.OutputStream
                    import kotlin.io.encoding.Base64
                    import kotlin.io.encoding.encodingWith

                    fun openEncoder(file: File): OutputStream {
                        val stream: OutputStream = file.outputStream()
                        return stream.encodingWith(Base64.Default)
                    }

            """,
            // testOutputStreamEncodingWithAcceptsAllBase64Variants
            """
            package sample1

                    import java.io.File
                    import java.io.OutputStream
                    import kotlin.io.encoding.Base64
                    import kotlin.io.encoding.encodingWith

                    fun openVariants(file: File): List<OutputStream> {
                        val stream: OutputStream = file.outputStream()
                        return listOf(
                            stream.encodingWith(Base64.Default),
                            stream.encodingWith(Base64.UrlSafe),
                            stream.encodingWith(Base64.Mime),
                            stream.encodingWith(Base64.Pem),
                        )
                    }

            """,
            // testOutputStreamEncodingWithChainedMemberCallsResolve
            """
            package sample2

                    import java.io.File
                    import java.io.OutputStream
                    import kotlin.io.encoding.Base64
                    import kotlin.io.encoding.encodingWith

                    fun writeAndClose(file: File) {
                        val stream: OutputStream = file.outputStream()
                        val encoder = stream.encodingWith(Base64.Default)
                        encoder.write(0x4B)
                        encoder.flush()
                        encoder.close()
                    }

            """,
            // testOutputStreamEncodingWithExternalLinkNameIsRegisteredOnWrapperSymbol
            """
            package sample3

                    import java.io.OutputStream
                    import kotlin.io.encoding.Base64
                    import kotlin.io.encoding.encodingWith

                    fun stub(stream: OutputStream): OutputStream = stream.encodingWith(Base64.Default)

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testOutputStreamEncodingWithResolves ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let diagnostics = sample0Diagnostics.map(\.message)
                #expect(
                    !sample0Diagnostics.contains { $0.severity == .error },
                    "OutputStream.encodingWith(base64) extension function in kotlin.io.encoding should resolve: \(diagnostics)"
                )

                let symbols = sema.symbols
                let types = sema.types

                let outputStreamSymbol = try #require(
                    symbols.lookup(fqName: ["java", "io", "OutputStream"].map(interner.intern))
                )
                let base64Symbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "io", "encoding", "Base64"].map(interner.intern))
                )

                let outputStreamType = types.make(.classType(ClassType(
                    classSymbol: outputStreamSymbol, args: [], nullability: .nonNull
                )))
                let base64Type = types.make(.classType(ClassType(
                    classSymbol: base64Symbol, args: [], nullability: .nonNull
                )))

                let encodingWithSymbols = symbols.lookupAll(
                    fqName: ["kotlin", "io", "encoding", "encodingWith"].map(interner.intern)
                )
                let encodingWith = try #require(encodingWithSymbols.first { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == outputStreamType
                        && signature.parameterTypes == [base64Type]
                        && signature.returnType == outputStreamType
                }, "Sema should register an OutputStream.encodingWith(Base64) extension")

                let signature = try #require(symbols.functionSignature(for: encodingWith))
                #expect(signature.valueParameterHasDefaultValues == [false])
                #expect(signature.valueParameterIsVararg == [false])

            }

            // === testOutputStreamEncodingWithAcceptsAllBase64Variants ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let diagnostics = sample1Diagnostics.map(\.message)
                #expect(
                    !sample1Diagnostics.contains { $0.severity == .error },
                    "OutputStream.encodingWith should accept every Base64 variant: \(diagnostics)"
                )

            }

            // === testOutputStreamEncodingWithChainedMemberCallsResolve ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let diagnostics = sample2Diagnostics.map(\.message)
                #expect(
                    !sample2Diagnostics.contains { $0.severity == .error },
                    "Chained OutputStream member calls after encodingWith should resolve: \(diagnostics)"
                )

            }

            // === testOutputStreamEncodingWithExternalLinkNameIsRegisteredOnWrapperSymbol ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let symbols = sema.symbols

                let wrapperCandidates = symbols.lookupAll(
                    fqName: ["kotlin", "io", "encoding", "__outputStreamEncodingWith"].map(interner.intern)
                )
                let wrapper = try #require(
                    wrapperCandidates.first { symbols.externalLinkName(for: $0) != nil },
                    "Sema should register the private __outputStreamEncodingWith bridge"
                )
                #expect(
                    symbols.externalLinkName(for: wrapper) == "__kk_output_stream_encodingWith"
                )

            }

        }
    }

}

#endif
