#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-IO-FN-013: Validates that `InputStream.copyTo(out, bufferSize)` resolves
/// through Sema for the `java.io.InputStream` receiver and produces a `Long` value.
///
/// Kotlin signature:
///   public fun InputStream.copyTo(
///       out: OutputStream,
///       bufferSize: Int = DEFAULT_BUFFER_SIZE
///   ): Long
///
/// The runtime link name exercised here is `kk_input_stream_copyTo`.
@Suite
struct InputStreamCopyToFunctionTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        import java.io.File
        import java.io.InputStream
        import java.io.OutputStream

        fun copy(src: File, dst: File): Long {
            val input: InputStream = src.inputStream()
            val output: OutputStream = dst.outputStream()
            return input.copyTo(output)
        }
        """,
        """
        package sample1
        import java.io.File
        import java.io.InputStream
        import java.io.OutputStream

        fun copyWithBuffer(src: File, dst: File): Long {
            val input: InputStream = src.inputStream()
            val output: OutputStream = dst.outputStream()
            return input.copyTo(output, 4096)
        }
        """,
        """
        package sample2
        import java.io.File
        import java.io.InputStream
        import java.io.OutputStream

        fun countBytes(src: File, dst: File): Long {
            val input: InputStream = src.inputStream()
            val output: OutputStream = dst.outputStream()
            val bytesCopied: Long = input.copyTo(output)
            return bytesCopied
        }
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

    // MARK: - Default bufferSize overload

    @Test func testInputStreamCopyToWithDefaultBufferSizeResolves() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected InputStream.copyTo(out) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Explicit bufferSize overload

    @Test func testInputStreamCopyToWithExplicitBufferSizeResolves() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected InputStream.copyTo(out, bufferSize) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - Return type is Long

    @Test func testInputStreamCopyToReturnTypeIsLong() throws {

        let ctx = try sharedCtx()
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected InputStream.copyTo return type Long to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
#endif
