#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-PATH-FN-042: Validates that the `writer` extension function on
/// `kotlin.io.path.Path` is wired through Sema with the expected
/// charset/options signature and resolves to `kk_path_writer`.
///
/// Kotlin signature:
///
///     public actual fun Path.writer(
///         charset: Charset = Charsets.UTF_8,
///         vararg options: OpenOption
///     ): BufferedWriter
@Suite
struct PathWriterFunctionTests {

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
            // testPathWriterDefaultCharsetResolves
            """
            package sample0

                    import java.io.BufferedWriter
                    import java.nio.file.OpenOption
                    import kotlin.io.path.Path
                    import kotlin.io.path.writer

                    fun openWriter(path: Path): BufferedWriter = path.writer()

            """,
            // testPathWriterExplicitCharsetResolves
            """
            package sample1

                    import java.io.BufferedWriter
                    import java.nio.file.OpenOption
                    import kotlin.io.path.Path
                    import kotlin.io.path.writer
                    import kotlin.text.Charsets

                    fun openWriter(path: Path): BufferedWriter = path.writer(Charsets.UTF_8)

            """,
            // testPathWriterWithOpenOptionResolves
            """
            package sample2

                    import java.io.BufferedWriter
                    import java.nio.file.OpenOption
                    import kotlin.io.path.Path
                    import kotlin.io.path.writer
                    import kotlin.text.Charsets

                    fun openWriter(path: Path, option: OpenOption): BufferedWriter =
                        path.writer(Charsets.UTF_8, option)

            """,
            // testPathWriterReturnTypeIsBufferedWriter
            """
            package sample3

                    import java.io.BufferedWriter
                    import kotlin.io.path.Path
                    import kotlin.io.path.writer

                    fun check(path: Path): BufferedWriter {
                        val w: BufferedWriter = path.writer()
                        return w
                    }

            """,
            // testPathWriterChainedWriteFlushCloseResolve
            """
            package sample4

                    import kotlin.io.path.Path
                    import kotlin.io.path.writer

                    fun writeAndClose(path: Path) {
                        val writer = path.writer()
                        writer.write("hello")
                        writer.newLine()
                        writer.flush()
                        writer.close()
                    }

            """,
            // testPathWriterUseBlockResolves
            """
            package sample5

                    import kotlin.io.path.Path
                    import kotlin.io.path.writer

                    fun writeOneLiner(path: Path) {
                        path.writer().use { it.write("data") }
                    }

            """,
            // testPathWriterExtensionFunctionSurfaceIsRegistered
            """
            package sample6

                    import java.io.BufferedWriter
                    import java.nio.file.OpenOption
                    import kotlin.io.path.Path
                    import kotlin.io.path.writer
                    import kotlin.text.Charsets

                    fun stub(path: Path, option: OpenOption): BufferedWriter = path.writer(Charsets.UTF_8, option)

            """,
            // testPathWriterCallBindingAndReturnType
            """
            package sample7

                    import java.io.BufferedWriter
                    import java.nio.file.OpenOption
                    import kotlin.io.path.Path
                    import kotlin.io.path.writer
                    import kotlin.text.Charsets

                    fun writers(path: Path, option: OpenOption): BufferedWriter {
                        val first: BufferedWriter = path.writer()
                        val second: BufferedWriter = path.writer(Charsets.UTF_8, option)
                        return second
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testPathWriterDefaultCharsetResolves ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Path.writer() with default charset should resolve: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testPathWriterExplicitCharsetResolves ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Path.writer(charset) should resolve: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testPathWriterWithOpenOptionResolves ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let errors = sample2Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Path.writer(charset, options) should resolve: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testPathWriterReturnTypeIsBufferedWriter ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let errors = sample3Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Path.writer() return type should be BufferedWriter: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testPathWriterChainedWriteFlushCloseResolve ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let errors = sample4Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Chained BufferedWriter member calls after Path.writer() should resolve: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testPathWriterUseBlockResolves ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let errors = sample5Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Path.writer().use { } should resolve: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testPathWriterExtensionFunctionSurfaceIsRegistered ===

            do {

                let sample6Path = paths[6]

                let filePath = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                #expect(
                    !sample6Diagnostics.contains { $0.severity == .error },
                    "Path.writer(charset, options) should resolve without errors: \(sample6Diagnostics.map(\.message))"
                )

                let symbols = sema.symbols
                let types = sema.types

                let pathSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
                )
                let charsetSymbol = try #require(
                    symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern))
                )
                let openOptionSymbol = try #require(
                    symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern))
                )
                let bufferedWriterSymbol = try #require(
                    symbols.lookup(fqName: ["java", "io", "BufferedWriter"].map(interner.intern))
                )

                let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
                let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
                let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
                let bufferedWriterType = types.make(.classType(ClassType(classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull)))

                let writerSymbols = symbols.lookupAll(
                    fqName: ["kotlin", "io", "path", "writer"].map(interner.intern)
                )
                let writer = try #require(
                    writerSymbols.first { symbolID in
                        guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                        return signature.receiverType == pathType
                            && signature.parameterTypes == [charsetType, openOptionType]
                            && signature.returnType == bufferedWriterType
                    },
                    "Expected kotlin.io.path.writer with receiver=Path, params=[Charset, OpenOption], ret=BufferedWriter"
                )

                #expect(
                    symbols.externalLinkName(for: writer) == "kk_path_writer"
                )

                let signature = try #require(symbols.functionSignature(for: writer))
                #expect(signature.valueParameterHasDefaultValues == [true, false])
                #expect(signature.valueParameterIsVararg == [false, true])

            }

            // === testPathWriterCallBindingAndReturnType ===

            do {

                let sample7Path = paths[7]

                let filePath = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                #expect(
                    !sample7Diagnostics.contains { $0.severity == .error },
                    "Path.writer() calls should resolve: \(sample7Diagnostics.map(\.message))"
                )

                let symbols = sema.symbols
                let types = sema.types

                let bufferedWriterSymbol = try #require(
                    symbols.lookup(fqName: ["java", "io", "BufferedWriter"].map(interner.intern))
                )
                let bufferedWriterType = types.make(.classType(ClassType(
                    classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull
                )))

                let callExprs = ast.arena.exprs.indices.compactMap { index -> ExprID? in
                    let exprID = ExprID(rawValue: Int32(index))
                    guard let expr = ast.arena.expr(exprID),
                          case let .memberCall(_, callee, _, _, range) = expr,
                          ctx.sourceManager.path(of: range.start.file) == sample7Path,
                          interner.resolve(callee) == "writer"
                    else { return nil }
                    return exprID
                }
                #expect(callExprs.count == 2)
                for callExpr in callExprs {
                    #expect(sema.bindings.exprTypes[callExpr] == bufferedWriterType)
                }

            }

        }
    }

}

#endif
