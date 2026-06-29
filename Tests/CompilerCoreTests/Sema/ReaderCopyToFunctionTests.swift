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

    @Test func testReaderCopyToWithExplicitBufferSizeResolves() throws {
        let source = """
        import java.io.BufferedReader
        import java.io.BufferedWriter
        import java.io.File
        import kotlin.io.copyTo

        fun copyAll(src: File, dst: File): Long {
            val reader: BufferedReader = src.bufferedReader()
            val writer: BufferedWriter = dst.bufferedWriter()
            return reader.copyTo(writer, 8 * 1024)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "Reader.copyTo(out, bufferSize) extension function in kotlin.io should resolve: \(diagnostics)")
            )
        }
    }

    // MARK: - Default-bufferSize overload (no second argument) resolves

    @Test func testReaderCopyToWithDefaultBufferSizeResolves() throws {
        let source = """
        import java.io.BufferedReader
        import java.io.BufferedWriter
        import java.io.File
        import kotlin.io.copyTo

        fun copyAll(src: File, dst: File): Long {
            val reader: BufferedReader = src.bufferedReader()
            val writer: BufferedWriter = dst.bufferedWriter()
            return reader.copyTo(writer)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "Reader.copyTo(out) with default bufferSize should resolve: \(diagnostics)")
            )
        }
    }

    // MARK: - Reader / Writer are registered in java.io

    @Test func testReaderAndWriterTypesAreRegistered() throws {
        let source = """
        import java.io.Reader
        import java.io.Writer

        fun stub(reader: Reader, writer: Writer): Unit {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "java.io.Reader / java.io.Writer should be declared as synthetic class symbols: \(diagnostics)")
            )

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            #expect(symbols.lookup(fqName: ["java", "io", "Reader"].map(interner.intern)) != nil)
            #expect(symbols.lookup(fqName: ["java", "io", "Writer"].map(interner.intern)) != nil)
        }
    }

    // MARK: - BufferedReader / BufferedWriter are Reader / Writer subtypes

    @Test func testBufferedReaderAndWriterFlowThroughReaderWriterReceivers() throws {
        // `Reader.copyTo(out: Writer, ...)` must accept BufferedReader / BufferedWriter
        // as receiver / argument because BufferedReader extends Reader and
        // BufferedWriter extends Writer in the JDK class hierarchy.  This test
        // pins that subtype relationship by asking Sema to type-check a call
        // where the receiver / argument are declared as the concrete subtypes.
        let source = """
        import java.io.File
        import kotlin.io.copyTo

        fun copyAll(src: File, dst: File) {
            src.bufferedReader().copyTo(dst.bufferedWriter())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "BufferedReader / BufferedWriter should satisfy the Reader / Writer surface of copyTo: \(diagnostics)")
            )
        }
    }

    // MARK: - External link name is wired through to kk_reader_copyTo

    @Test func testReaderCopyToExternalLinkNameIsRegisteredOnSymbol() throws {
        let source = """
        import java.io.Reader
        import java.io.Writer
        import kotlin.io.copyTo

        fun stub(reader: Reader, writer: Writer): Long = reader.copyTo(writer, 4096)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
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
    }

    // MARK: - Call site binds to the expected copyTo overload

    @Test func testReaderCopyToCallSiteBindsToRegisteredSymbol() throws {
        let source = """
        import java.io.File
        import kotlin.io.copyTo

        fun copyAll(src: File, dst: File) {
            val reader = src.bufferedReader()
            val writer = dst.bufferedWriter()
            reader.copyTo(writer, 1024)
            reader.copyTo(writer)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)

            let callExprs = memberCallExprIDs(named: "copyTo", in: ast, interner: interner)
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
    }

    // MARK: - Closeable .use {} continues to work after Reader / Writer hoisting

    @Test func testBufferedReaderAndWriterRemainCloseable() throws {
        // STDLIB-IO-FN-014 moves the BufferedReader / BufferedWriter -> Closeable
        // edge through the new Reader / Writer intermediaries.  Make sure the
        // `.use { }` extension still resolves on both.
        let source = """
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
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(
                !(ctx.diagnostics.hasError),
                Comment(rawValue: "BufferedReader / BufferedWriter must remain Closeable after the Reader/Writer hoist: \(diagnostics)")
            )
        }
    }
}
#endif
