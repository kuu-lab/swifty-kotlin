@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-4031: `BufferedReader` accepts any `java.io.Reader` — Kotlin-source
    /// subclasses (StringReader, user subclasses) reach the runtime through
    /// the Reader `read(CharArray, Int, Int)` vtable slot, so wrapping,
    /// `readText`/`copyTo`, `is`/`as`, and close propagation all behave like
    /// the JVM instead of panicking on an "invalid Reader handle".
    @Test func testJavaIOBufferedReaderWrapsKotlinReaders() throws {
        let source = """
        import java.io.BufferedReader
        import java.io.IOException
        import java.io.InputStreamReader
        import java.io.Reader
        import java.io.StringReader
        import java.io.StringWriter

        class PrefixReader(private val source: String) : Reader() {
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
                println("prefix close")
            }
        }

        fun main() {
            // Ticket MRE: BufferedReader over a Kotlin-source StringReader.
            val lines = BufferedReader(StringReader("l1\\nl2"))
            println(lines.readLine())
            println(lines.readLine())
            println(lines.readLine())

            // read()/ready() reach the same Kotlin reader state.
            val chars = BufferedReader(StringReader("x\\ny"))
            println(chars.ready())
            println(chars.read())
            println(chars.readLine())
            println(chars.readLine())

            // A user-defined Reader subclass dispatches identically.
            val custom = BufferedReader(PrefixReader("c1\\nc2"))
            println(custom.readLine())
            println(custom.readLine())
            custom.close()

            // Reader-typed receivers: readText / copyTo / virtual read range.
            val textReader: Reader = StringReader("tail")
            println(textReader.readText())

            val sink = StringWriter()
            StringReader("copied").copyTo(sink)
            println(sink.toString())

            val rangeReader: Reader = BufferedReader(StringReader("abcdef"))
            val buffer = CharArray(4)
            buffer[0] = ' '
            println(rangeReader.read(buffer, 1, 3))
            println(String(buffer))

            // Nested wraps and nominal identity checks.
            println(BufferedReader(BufferedReader(StringReader("deep"))).readLine())
            val any: Reader = BufferedReader(StringReader("k"))
            println(any is BufferedReader)
            println(any is Reader)
            println((any as BufferedReader).readLine())
        }
        """
        let expected = """
        l1
        l2
        null
        true
        120

        y
        c1
        c2
        prefix close
        tail
        copied
        3
         abc
        deep
        true
        true
        k

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
                        moduleName: "JavaIOReaderWrap",
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
