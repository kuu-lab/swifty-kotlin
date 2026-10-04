#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-IO-FN-003: Validates that `InputStream.buffered(bufferSize)` resolves
/// through Sema for the `java.io.InputStream` receiver and produces a
/// `java.io.BufferedInputStream` value that can be used as an `InputStream`
/// (closing, reading, .use {} etc.).
///
/// The runtime link names exercised here are `kk_input_stream_buffered_default`
/// (zero-arg overload) and `kk_input_stream_buffered` (bufferSize overload).
@Suite
struct InputStreamBufferedFunctionTests {

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testInputStreamBufferedNoArgsResolves
            """
            package sample0

                    import java.io.BufferedInputStream
                    import java.io.InputStream

                    fun open(text: String): BufferedInputStream {
                        val raw: InputStream = text.byteInputStream()
                        return raw.buffered()
                    }

            """,
            // testInputStreamBufferedWithBufferSizeResolves
            """
            package sample1

                    import java.io.BufferedInputStream
                    import java.io.InputStream

                    fun openWithSize(text: String): BufferedInputStream {
                        val raw: InputStream = text.byteInputStream()
                        return raw.buffered(8 * 1024)
                    }

            """,
            // testBufferedInputStreamFlowsThroughInputStreamSurface
            """
            package sample2

                    import java.io.BufferedInputStream

                    fun consume(text: String): Int {
                        val buffered: BufferedInputStream = text.byteInputStream().buffered()
                        val byte: Int = buffered.read()
                        val remaining: Int = buffered.available()
                        buffered.close()
                        return byte + remaining
                    }

                    fun useIt(text: String): Int {
                        return text.byteInputStream().buffered(4096).use { stream ->
                            stream.read()
                        }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            _ = try #require(ctx.sema)


            // === testInputStreamBufferedNoArgsResolves ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected InputStream.buffered() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testInputStreamBufferedWithBufferSizeResolves ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected InputStream.buffered(bufferSize) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testBufferedInputStreamFlowsThroughInputStreamSurface ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                // BufferedInputStream extends InputStream, so all read/skip/available/close
                // methods on InputStream remain callable via the buffered handle, and
                // .use { } works because InputStream is a Closeable subtype.
                let errors = sample2Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected BufferedInputStream to be usable as an InputStream, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

        }
    }

}

#endif
