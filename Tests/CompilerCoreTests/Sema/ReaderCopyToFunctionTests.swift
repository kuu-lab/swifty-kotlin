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
///   - `__kk_reader_copyTo` (explicit bufferSize)
///   - `__kk_reader_copyTo_default` (omitted bufferSize, uses the JVM default)
@Suite
struct ReaderCopyToFunctionTests {

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
                #expect(symbols.externalLinkName(for: twoArg) == "__kk_reader_copyTo")

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
                #expect(symbols.externalLinkName(for: oneArg) == "__kk_reader_copyTo_default")

            }

            // === testReaderCopyToCallSiteBindsToRegisteredSymbol ===

            do {

                let sample5Path = paths[5]



                let callExprs = memberCallExprIDs(named: "copyTo", in: ast, path: sample5Path, ctx: ctx, interner: interner)
                #expect(callExprs.count == 2, "Expected two copyTo call sites")

                let externalNames: [String?] = callExprs.compactMap { exprID in
                    guard let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee else {
                        return nil
                    }
                    return sema.symbols.externalLinkName(for: chosen)
                }
                #expect(externalNames.contains("__kk_reader_copyTo"))
                #expect(externalNames.contains("__kk_reader_copyTo_default"))

            }

            // === testBufferedReaderAndWriterRemainCloseable ===

            do {

                let sample6Path = paths[6]


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
