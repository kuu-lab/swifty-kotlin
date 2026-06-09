@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-030: kotlin.io common - File read/write codegen tests
extension CodegenBackendIntegrationTests {

    // MARK: - File.readText / writeText / appendText

    func testCodegenFileWriteTextAndReadText() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_file_rw_codegen.txt"
            val file = File(path)
            file.delete()

            file.writeText("hello world")
            val text = file.readText()
            println(text)

            file.delete()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FileWriteReadText",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "hello world\n")
        }
    }

    func testCodegenFileAppendText() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_file_append_text_codegen.txt"
            val file = File(path)
            file.delete()

            file.writeText("line1\n")
            file.appendText("line2\n")
            val text = file.readText()
            print(text)

            file.delete()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FileAppendText",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "line1\nline2\n")
        }
    }

    func testCodegenFileReadLines() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_file_read_lines_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("alpha\nbeta\ngamma")

            val lines = file.readLines()
            println(lines.size)
            for (line in lines) {
                println(line)
            }

            file.delete()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FileReadLines",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\nalpha\nbeta\ngamma\n")
        }
    }
}
