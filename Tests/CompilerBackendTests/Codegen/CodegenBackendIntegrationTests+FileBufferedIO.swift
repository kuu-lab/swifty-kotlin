@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// STDLIB-030: kotlin.io common - bufferedReader/bufferedWriter codegen tests
extension CodegenBackendIntegrationTests {

    // MARK: - File.bufferedReader().use {}

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FileBufferedReaderUseReadText",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "buffered reader text\n")
        }
    }

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FileBufferedReaderReadLine",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "first\nsecond\nthird\nnull\n")
        }
    }

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FileBufferedReaderReadLines",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\nx\ny\nz\n")
        }
    }

    // STDLIB-IO-USE-001: bufferedReader().use { reader -> reader.readLines() }
    // Regression: use{} returning a heap-allocated List<String> previously
    // failed codegen because the lambda result type was inferred as Any instead
    // of List<String>, making subsequent member accesses (lines.size) unresolvable.
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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FileBufferedReaderUseBlockReadLines",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                "3\nalpha\nbeta\ngamma\n"
            )
        }
    }

    // MARK: - File.bufferedWriter().use {}

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FileBufferedWriterUseWrite",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "written by bufferedWriter\n")
        }
    }

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FileBufferedWriterMultipleLines",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "2\nline A\nline B\n")
        }
    }

    // MARK: - Reader.readText() extension

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ReaderReadTextExtension",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "reader readText result\n")
        }
    }
}
