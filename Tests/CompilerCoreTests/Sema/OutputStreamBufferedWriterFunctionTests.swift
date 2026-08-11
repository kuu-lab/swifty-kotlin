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

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
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
        """
        package sample3
        import java.io.BufferedWriter
        import java.io.OutputStream
        import kotlin.io.bufferedWriter
        import kotlin.text.Charsets

        fun stub(stream: OutputStream): BufferedWriter = stream.bufferedWriter(Charsets.UTF_8)
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }
    /// `OutputStream.bufferedWriter(charset)` should resolve to the
    /// synthetic extension function in `kotlin.io` and return a
    /// `java.io.BufferedWriter`.
    @Test func testOutputStreamBufferedWriterWithExplicitCharsetResolves() throws {

        let ctx = try sharedCtx()
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(
                !(ctx.diagnostics.hasError),
                "OutputStream.bufferedWriter(charset) extension function in kotlin.io should resolve: \(diagnostics)"
            )

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
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

    /// `OutputStream.bufferedWriter()` with no arguments should resolve via
    /// the `charset` parameter's default value (`Charsets.UTF_8`).
    @Test func testOutputStreamBufferedWriterWithDefaultCharsetResolves() throws {

        let ctx = try sharedCtx()
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(
                !(ctx.diagnostics.hasError),
                "OutputStream.bufferedWriter() with default charset should resolve: \(diagnostics)"
            )

    }

    /// The returned `BufferedWriter` should be usable for `.write`, `.flush`,
    /// and `.close` member calls — confirming the type chain stays intact.
    @Test func testOutputStreamBufferedWriterChainedMemberCallsResolve() throws {

        let ctx = try sharedCtx()
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(
                !(ctx.diagnostics.hasError),
                "Chained BufferedWriter member calls after OutputStream.bufferedWriter should resolve: \(diagnostics)"
            )

    }

    /// The Sema layer should record the external link name on the symbol so
    /// codegen can resolve it to `kk_output_stream_bufferedWriter` later in
    /// the pipeline.
    @Test func testOutputStreamBufferedWriterExternalLinkNameIsRegisteredOnSymbol() throws {

        let ctx = try sharedCtx()
            let interner = ctx.interner
            let sema = try #require(ctx.sema)
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
#endif
