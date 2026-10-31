import Testing
@testable import CompilerCore
@testable import CompilerTestSupport

/// KUU-3860: the synthetic `java.io` stream/reader/writer classes must keep
/// `java.io.Closeable` (and transitively `java.lang.AutoCloseable`) as a
/// supertype — JVM streams implement it, so parameters, assignments and
/// `is` checks against it must typecheck.
@Suite
struct JavaIOCloseableConformanceTests {
    @Test
    func streamTypesConformToJavaIOCloseable() throws {
        let source = """
        import java.io.InputStream
        import java.io.OutputStream
        import java.io.ByteArrayInputStream
        import java.io.Reader
        import java.io.BufferedReader
        import java.io.Writer
        import java.io.BufferedWriter

        fun useCloseable(c: java.io.Closeable) { c.close() }
        fun useAutoCloseable(a: java.lang.AutoCloseable) { a.close() }

        fun streams() {
            useCloseable("abc".byteInputStream())
            val s: InputStream = ByteArrayInputStream("abc".toByteArray())
            useCloseable(s)
            useAutoCloseable(s)
            val c: java.io.Closeable = s
            val a: java.lang.AutoCloseable = s
            val isCloseable: Boolean = s is java.io.Closeable
            val isAutoCloseable: Boolean = s is java.lang.AutoCloseable
        }

        fun output(o: OutputStream) { useCloseable(o) }
        fun reader(r: Reader) { useCloseable(r) }
        fun bufferedReader(r: BufferedReader) { useCloseable(r) }
        fun writer(w: Writer) { useCloseable(w) }
        fun bufferedWriter(w: BufferedWriter) { useCloseable(w) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "diagnostics: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    @Test
    func closeResolvesThroughJavaCloseableInterfaces() throws {
        // `c.close()` on a java.io.Closeable / java.lang.AutoCloseable
        // receiver must resolve to the shared close member (itable dispatch),
        // not fail member resolution.
        let source = """
        import java.io.InputStream
        fun callOnCloseable(c: java.io.Closeable) { c.close() }
        fun callOnAutoCloseable(a: java.lang.AutoCloseable) { a.close() }
        fun viaParam(s: InputStream) { callOnCloseable(s); callOnAutoCloseable(s) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "diagnostics: \(ctx.diagnostics.diagnostics)"
            )
        }
    }
}
