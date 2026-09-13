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
    /// codegen can resolve it to `__kk_output_stream_bufferedWriter` later in
    /// the pipeline.

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

            _ = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testOutputStreamBufferedWriterWithExplicitCharsetResolves ===

            do {

                let sample0Path = paths[0]


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
                    symbols.externalLinkName(for: bufferedWriter) == "__kk_output_stream_bufferedWriter"
                )

                let signature = try #require(symbols.functionSignature(for: bufferedWriter))
                #expect(signature.valueParameterHasDefaultValues == [true])
                #expect(signature.valueParameterIsVararg == [false])

            }

            // === testOutputStreamBufferedWriterWithDefaultCharsetResolves ===

            do {

                let sample1Path = paths[1]


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


                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let diagnostics = sample2Diagnostics.map(\.message)
                #expect(
                    !(sample2Diagnostics.contains { $0.severity == .error }),
                    "Chained BufferedWriter member calls after OutputStream.bufferedWriter should resolve: \(diagnostics)"
                )

            }

            // === testOutputStreamBufferedWriterExternalLinkNameIsRegisteredOnSymbol ===

            do {




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
                    symbols.externalLinkName(for: bufferedWriter) == "__kk_output_stream_bufferedWriter"
                )

            }

        }
    }

}

#endif
