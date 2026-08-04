#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Sema-surface tests for `kotlin.io.copyTo` extension function on
/// `java.io.Reader` (STDLIB-IO-FN-014).
///
/// Kotlin signature:
///   public fun Reader.copyTo(out: Writer, bufferSize: Int = DEFAULT_BUFFER_SIZE): Long
///
/// The runtime link names exercised here are:
///   - `kk_reader_copyTo` (explicit bufferSize)
///   - `kk_reader_copyTo_default` (omitted bufferSize, uses the JVM default)
@Suite
struct ReaderCopyToFunctionTests {

    // MARK: - Helpers

    // MARK: - Two-arg overload resolves and types as Long

    // MARK: - Default-bufferSize overload (no second argument) resolves

    // MARK: - Reader / Writer are registered in java.io

    // MARK: - BufferedReader / BufferedWriter are Reader / Writer subtypes

    // MARK: - External link name is wired through to kk_reader_copyTo

    // MARK: - Call site binds to the expected copyTo overload

    // MARK: - Closeable .use {} continues to work after Reader / Writer hoisting

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
            // testReaderCopyToWithExplicitBufferSizeResolves
            """
            package sample0

                    import java.io.BufferedReader
                    import java.io.BufferedWriter
                    import java.io.File
                    import kotlin.io.copyTo

                    fun copyAll(src: File, dst: File): Long {
                        val reader: BufferedReader = src.bufferedReader()
                        val writer: BufferedWriter = dst.bufferedWriter()
                        return reader.copyTo(writer, 8 * 1024)
                    }

            """,
            // testReaderCopyToWithDefaultBufferSizeResolves
            """
            package sample1

                    import java.io.BufferedReader
                    import java.io.BufferedWriter
                    import java.io.File
                    import kotlin.io.copyTo

                    fun copyAll(src: File, dst: File): Long {
                        val reader: BufferedReader = src.bufferedReader()
                        val writer: BufferedWriter = dst.bufferedWriter()
                        return reader.copyTo(writer)
                    }

            """,
            // testReaderAndWriterTypesAreRegistered
            """
            package sample2

                    import java.io.Reader
                    import java.io.Writer

                    fun stub(reader: Reader, writer: Writer): Unit {}

            """,
            // testBufferedReaderAndWriterFlowThroughReaderWriterReceivers
            """
            package sample3

                    import java.io.File
                    import kotlin.io.copyTo

                    fun copyAll(src: File, dst: File) {
                        src.bufferedReader().copyTo(dst.bufferedWriter())
                    }

            """,
            // testReaderCopyToExternalLinkNameIsRegisteredOnSymbol
            """
            package sample4

                    import java.io.Reader
                    import java.io.Writer
                    import kotlin.io.copyTo

                    fun stub(reader: Reader, writer: Writer): Long = reader.copyTo(writer, 4096)

            """,
            // testReaderCopyToCallSiteBindsToRegisteredSymbol
            """
            package sample5

                    import java.io.File
                    import kotlin.io.copyTo

                    fun copyAll(src: File, dst: File) {
                        val reader = src.bufferedReader()
                        val writer = dst.bufferedWriter()
                        reader.copyTo(writer, 1024)
                        reader.copyTo(writer)
                    }

            """,
            // testBufferedReaderAndWriterRemainCloseable
            """
            package sample6

                    import java.io.File

                    fun copyAll(src: File, dst: File) {
                        src.bufferedReader().use { reader ->
                            dst.bufferedWriter().use { writer ->
                                while (true) {
                                    val line = reader.readLine() ?: break
                                    writer.write(line)
                                    writer.newLine()
                                }
                            }
                        }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testReaderCopyToWithExplicitBufferSizeResolves ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let diagnostics = sample0Diagnostics.map(\.message)
                #expect(
                    !(sample0Diagnostics.contains { $0.severity == .error }),
                    Comment(rawValue: "Reader.copyTo(out, bufferSize) extension function in kotlin.io should resolve: \(diagnostics)")
                )

            }

            // === testReaderCopyToWithDefaultBufferSizeResolves ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let diagnostics = sample1Diagnostics.map(\.message)
                #expect(
                    !(sample1Diagnostics.contains { $0.severity == .error }),
                    Comment(rawValue: "Reader.copyTo(out) with default bufferSize should resolve: \(diagnostics)")
                )

            }

            // === testReaderAndWriterTypesAreRegistered ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let diagnostics = sample2Diagnostics.map(\.message)
                #expect(
                    !(sample2Diagnostics.contains { $0.severity == .error }),
                    Comment(rawValue: "java.io.Reader / java.io.Writer should be declared as synthetic class symbols: \(diagnostics)")
                )

                let symbols = sema.symbols
                #expect(symbols.lookup(fqName: ["java", "io", "Reader"].map(interner.intern)) != nil)
                #expect(symbols.lookup(fqName: ["java", "io", "Writer"].map(interner.intern)) != nil)

            }

            // === testBufferedReaderAndWriterFlowThroughReaderWriterReceivers ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                // `Reader.copyTo(out: Writer, ...)` must accept BufferedReader / BufferedWriter
                // as receiver / argument because BufferedReader extends Reader and
                // BufferedWriter extends Writer in the JDK class hierarchy.  This test
                // pins that subtype relationship by asking Sema to type-check a call
                // where the receiver / argument are declared as the concrete subtypes.
                    let diagnostics = sample3Diagnostics.map(\.message)
                    #expect(
                        !(sample3Diagnostics.contains { $0.severity == .error }),
                        Comment(rawValue: "BufferedReader / BufferedWriter should satisfy the Reader / Writer surface of copyTo: \(diagnostics)")
                    )

            }

            // === testReaderCopyToExternalLinkNameIsRegisteredOnSymbol ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let symbols = sema.symbols
                let types = sema.types

                let readerSymbol = try #require(
                    symbols.lookup(fqName: ["java", "io", "Reader"].map(interner.intern))
                )
                let writerSymbol = try #require(
                    symbols.lookup(fqName: ["java", "io", "Writer"].map(interner.intern))
                )
                let readerType = types.make(.classType(ClassType(
                    classSymbol: readerSymbol, args: [], nullability: .nonNull
                )))
                let writerType = types.make(.classType(ClassType(
                    classSymbol: writerSymbol, args: [], nullability: .nonNull
                )))

                let copyToCandidates = symbols.lookupAll(
                    fqName: ["kotlin", "io", "copyTo"].map(interner.intern)
                )

                let twoArg = try #require(copyToCandidates.first { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == readerType
                        && signature.parameterTypes == [writerType, types.intType]
                        && signature.returnType == types.longType
                })
                #expect(symbols.externalLinkName(for: twoArg) == "kk_reader_copyTo")

                let twoArgSignature = try #require(symbols.functionSignature(for: twoArg))
                #expect(twoArgSignature.valueParameterHasDefaultValues == [false, false])
                #expect(twoArgSignature.valueParameterIsVararg == [false, false])

                let oneArg = try #require(copyToCandidates.first { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == readerType
                        && signature.parameterTypes == [writerType]
                        && signature.returnType == types.longType
                })
                #expect(symbols.externalLinkName(for: oneArg) == "kk_reader_copyTo_default")

            }

            // === testReaderCopyToCallSiteBindsToRegisteredSymbol ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let callExprs = memberCallExprIDsInPath(named: "copyTo", in: ast, path: sample5Path, ctx: ctx, interner: interner)
                #expect(callExprs.count == 2, "Expected two copyTo call sites")

                let externalNames: [String?] = callExprs.compactMap { exprID in
                    guard let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee else {
                        return nil
                    }
                    return sema.symbols.externalLinkName(for: chosen)
                }
                #expect(externalNames.contains("kk_reader_copyTo"))
                #expect(externalNames.contains("kk_reader_copyTo_default"))

            }

            // === testBufferedReaderAndWriterRemainCloseable ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                // STDLIB-IO-FN-014 moves the BufferedReader / BufferedWriter -> Closeable
                // edge through the new Reader / Writer intermediaries.  Make sure the
                // `.use { }` extension still resolves on both.
                    let diagnostics = sample6Diagnostics.map(\.message)
                    #expect(
                        !(sample6Diagnostics.contains { $0.severity == .error }),
                        Comment(rawValue: "BufferedReader / BufferedWriter must remain Closeable after the Reader/Writer hoist: \(diagnostics)")
                    )

            }

        }
    }

}

#endif
