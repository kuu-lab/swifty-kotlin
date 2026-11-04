@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-4044: `java.io.Reader.read(CharArray)` — the JVM convenience
    /// overload that delegates to `read(cbuf, 0, cbuf.length)`. Registered
    /// as a concrete member on the synthetic `Reader` base so every
    /// `Reader`/`BufferedReader`/`InputStreamReader`/`StringReader` receiver
    /// resolves it; the `__kk_reader_read` bridge forwards to
    /// `__kk_reader_read_range`, which for Kotlin-source readers now
    /// dispatches the subclass's own 3-arg override straight into the
    /// caller's buffer — a transient charSource staging buffer previously
    /// swallowed every char past `length`, so chained bulk reads lost data.
    @Test func testJavaIOReaderBulkReadCharArray() throws {
        let source = """
        import java.io.BufferedReader
        import java.io.IOException
        import java.io.InputStreamReader
        import java.io.Reader
        import java.io.StringReader

        class CountingReader(private val source: String) : Reader() {
            private var index = 0
            private var closed = false

            override fun read(buffer: CharArray, offset: Int, length: Int): Int {
                if (closed) throw IOException("closed")
                if (offset < 0 || length < 0 || offset > buffer.size - length) {
                    throw IndexOutOfBoundsException()
                }
                if (length == 0) return 0
                if (index >= source.length) return -1
                var copied = 0
                while (copied < length && index < source.length) {
                    buffer[offset + copied] = source[index]
                    copied += 1
                    index += 1
                }
                return copied
            }

            override fun close() {
                closed = true
            }
        }

        fun main() {
            // Ticket MRE: StringReader.read(CharArray) — SEMA-0002 before.
            val sr = StringReader("line1\\nline2")
            val buf = CharArray(4)
            println(sr.read(buf))
            println(String(buf))
            println(sr.read(buf))
            println(String(buf))
            println(sr.read(buf))

            // BufferedReader box and InputStreamReader inherit the overload.
            val br = BufferedReader(StringReader("Hello"))
            val bbuf = CharArray(8)
            println(br.read(bbuf))
            println(String(bbuf))
            println(br.read(bbuf))

            val isr = InputStreamReader("ios".byteInputStream())
            val ibuf = CharArray(5)
            println(isr.read(ibuf))
            println(String(ibuf))

            // Reader-typed receivers: chained bulk reads must not drop the
            // chars past `length` that a transient charSource over-read.
            val kotlinReader: Reader = StringReader("wxyz")
            val kbuf = CharArray(2)
            println(kotlinReader.read(kbuf))
            println(String(kbuf))
            println(kotlinReader.read(kbuf))
            println(kotlinReader.read(kbuf))

            val boxedReader: Reader = BufferedReader(StringReader("abcdef"))
            val rbuf = CharArray(3)
            println(boxedReader.read(rbuf))
            println(String(rbuf))
            println(boxedReader.read(rbuf))
            println(boxedReader.read(rbuf))

            // 3-arg reads on Reader-typed receivers chain identically.
            val chained: Reader = StringReader("123456789")
            val cbuf = CharArray(6)
            println(chained.read(cbuf, 0, 4))
            println(chained.read(cbuf, 4, 2))
            println(String(cbuf))
            println(chained.read(cbuf))
            println(chained.read(cbuf))

            // User-defined Reader subclass through both receiver shapes.
            val custom = CountingReader("qwer")
            val ubuf = CharArray(3)
            println(custom.read(ubuf))
            println(String(ubuf))
            val customRef: Reader = CountingReader("asdf")
            println(customRef.read(ubuf))
            println(String(ubuf))
            println(customRef.read(ubuf))

            // JVM bounds contract: IndexOutOfBoundsException before any read.
            val bounds = StringReader("abc")
            try { bounds.read(buf, -1, 2); println("no-throw") } catch (e: IndexOutOfBoundsException) { println("ioobe-neg-off") }
            try { bounds.read(buf, 0, -1); println("no-throw") } catch (e: IndexOutOfBoundsException) { println("ioobe-neg-len") }
            try { bounds.read(buf, 3, 2); println("no-throw") } catch (e: IndexOutOfBoundsException) { println("ioobe-overrun") }
            try { bounds.read(buf, 5, 0); println("no-throw") } catch (e: IndexOutOfBoundsException) { println("ioobe-past-end") }
            val boxBounds = BufferedReader(StringReader("abc"))
            try { boxBounds.read(buf, 2, 3); println("no-throw") } catch (e: IndexOutOfBoundsException) { println("ioobe-box") }

            // len == 0 returns 0 without consuming.
            println(bounds.read(buf, 0, 0))
            println(bounds.read(CharArray(0)))
            println(bounds.read(buf))

            // Closed Kotlin reader surfaces IOException through both overloads.
            val closed = StringReader("abc")
            closed.close()
            try { closed.read(buf) } catch (e: IOException) { println("ioe-1arg") }
            try { closed.read(buf, 0, 2) } catch (e: IOException) { println("ioe-3arg") }
        }
        """
        let expected = """
        4
        line
        4
        1\nli
        3
        5
        Hello\u{0}\u{0}\u{0}
        -1
        3
        ios\u{0}\u{0}
        2
        wx
        2
        -1
        3
        abc
        3
        -1
        4
        2
        123456
        3
        -1
        3
        qwe
        3
        asd
        1
        ioobe-neg-off
        ioobe-neg-len
        ioobe-overrun
        ioobe-past-end
        ioobe-box
        0
        0
        3
        ioe-1arg
        ioe-3arg

        """
        let artifact = try Self.buildStdlibArtifact()
        for library in [nil, artifact] as [String?] {
            for level in [OptimizationLevel.O0, .O2] {
                try withTemporaryFile(contents: source) { inputPath in
                    let outputPath = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).path
                    defer { try? FileManager.default.removeItem(atPath: outputPath) }
                    let context = try runCodegenPipeline(
                        inputPath: inputPath,
                        moduleName: "JavaIOReaderBulkRead",
                        outputPath: outputPath,
                        optLevel: level,
                        allowDefaultStdlibLibrary: false,
                        stdlibLibraryPath: library
                    )
                    try assertNoDiagnosticErrors(context)
                    try LinkPhase().run(context)
                    let result = try CommandRunner.run(executable: outputPath, arguments: [])
                    #expect(result.exitCode == 0)
                    #expect(result.stderr.isEmpty)
                    #expect(result.stdout == expected)
                }
            }
        }
    }
}
