#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func runCodegenPipeline(
    inputPath: String,
    moduleName: String,
    emit: EmitMode,
    outputPath: String,
    irFlags: [String] = []
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        irFlags: irFlags
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    if emit == .kirDump {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for dump.")
        }
        let path = outputPath + ".kir"
        let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    } else {
        try CodegenPhase().run(ctx)
    }
    return ctx
}

// STDLIB-030: kotlin.io common - bufferedReader/bufferedWriter codegen tests
@Suite
struct CodegenBackendFileBufferedIOTests {

    @Test
    func testCodegenFileBufferedReaderUseReadText() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_br_readtext_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("buffered reader text")

            val text = file.bufferedReader().use { reader ->
                reader.readText()
            }
            println(text)

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "FileBufferedReaderUseReadText", expected: "buffered reader text\n")
    }

    @Test
    func testCodegenFileCopyToCatchesFileAlreadyExistsException() throws {
        let source = """
        import java.io.File
        import kotlin.io.FileAlreadyExistsException

        fun main() {
            val source = File("/tmp/kswiftk_copy_source.txt")
            val target = File("/tmp/kswiftk_copy_target.txt")
            source.delete()
            target.delete()
            source.writeText("source")
            target.writeText("target")

            try {
                source.copyTo(target)
                println("not caught")
            } catch (e: FileAlreadyExistsException) {
                println("already exists")
            }

            source.delete()
            try {
                source.copyTo(target, overwrite = true)
                println("not caught")
            } catch (e: kotlin.io.NoSuchFileException) {
                println("missing")
            }
            target.delete()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FileCopyToCatchesFileAlreadyExistsException",
            expected: "already exists\nmissing\n"
        )
    }

    @Test
    func testCodegenFileBufferedReaderReadLine() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_br_readline_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("first\nsecond\nthird")

            val reader = file.bufferedReader()
            println(reader.readLine())
            println(reader.readLine())
            println(reader.readLine())
            println(reader.readLine())
            reader.close()

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "FileBufferedReaderReadLine", expected: "first\nsecond\nthird\nnull\n")
    }

    @Test
    func testCodegenFileBufferedReaderReadLines() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_br_readlines_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("x\ny\nz")

            val reader = file.bufferedReader()
            val lines = reader.readLines()
            reader.close()
            println(lines.size)
            for (l in lines) println(l)

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "FileBufferedReaderReadLines", expected: "3\nx\ny\nz\n")
    }

    // STDLIB-IO-USE-001: bufferedReader().use { reader -> reader.readLines() }
    // Regression: use{} returning a heap-allocated List<String> previously
    // failed codegen because the lambda result type was inferred as Any instead
    // of List<String>, making subsequent member accesses (lines.size) unresolvable.
    @Test
    func testCodegenFileBufferedReaderUseBlockReadLines() throws {
        let tmpPath = "/tmp/kswiftk_buffered_reader_readLines_test.txt"
        try "alpha\nbeta\ngamma\n".write(toFile: tmpPath, atomically: true, encoding: .utf8)

        let source = """
        import java.io.File

        fun main() {
            val file = File("\(tmpPath)")
            val lines = file.bufferedReader().use { reader -> reader.readLines() }
            println(lines.size)
            for (line in lines) println(line)
        }
        """

        try assertKotlinOutput(source, moduleName: "FileBufferedReaderUseBlockReadLines", expected: "3\nalpha\nbeta\ngamma\n")
    }

    @Test
    func testCodegenFileBufferedWriterUseWrite() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_bw_write_codegen.txt"
            val file = File(path)
            file.delete()

            file.bufferedWriter().use { writer ->
                writer.write("written by bufferedWriter")
                writer.newLine()
            }

            val text = file.readText()
            print(text)

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "FileBufferedWriterUseWrite", expected: "written by bufferedWriter\n")
    }

    @Test
    func testCodegenFileBufferedWriterMultipleLines() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_bw_multiline_codegen.txt"
            val file = File(path)
            file.delete()

            val writer = file.bufferedWriter()
            writer.write("line A")
            writer.newLine()
            writer.write("line B")
            writer.newLine()
            writer.flush()
            writer.close()

            val lines = file.readLines()
            println(lines.size)
            for (l in lines) println(l)

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "FileBufferedWriterMultipleLines", expected: "2\nline A\nline B\n")
    }

    @Test
    func testCodegenReaderReadTextExtension() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_reader_readtext_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("reader readText result")

            val reader = file.bufferedReader()
            val text: String = reader.readText()
            reader.close()
            println(text)

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "ReaderReadTextExtension", expected: "reader readText result\n")
    }

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }
}
#endif

