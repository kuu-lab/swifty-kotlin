@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// STDLIB-030: kotlin.io common - useLines / forEachLine codegen tests
extension CodegenBackendIntegrationTests {

    // MARK: - File.useLines {}

    func testCodegenFileUseLines() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_file_uselines_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("alpha\nbeta\ngamma")

            val count = file.useLines { lines ->
                lines.count()
            }
            println(count)

            file.useLines { lines ->
                lines.forEach { line -> println(line) }
            }

            file.delete()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FileUseLines",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\nalpha\nbeta\ngamma\n")
        }
    }

    // MARK: - File.forEachLine {}

    func testCodegenFileForEachLine() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_file_foreachline_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("one\ntwo\nthree")

            file.forEachLine { line ->
                println(line)
            }

            file.delete()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FileForEachLine",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "one\ntwo\nthree\n")
        }
    }

    // MARK: - BufferedReader.useLines {}

    func testCodegenBufferedReaderUseLines() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_br_uselines_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("p\nq\nr")

            file.bufferedReader().useLines { lines ->
                lines.forEach { l -> println(l) }
            }

            file.delete()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "BufferedReaderUseLines",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "p\nq\nr\n")
        }
    }

    // MARK: - BufferedReader.forEachLine {}

    func testCodegenBufferedReaderForEachLine() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_br_foreachline_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("row1\nrow2\nrow3")

            val reader = file.bufferedReader()
            reader.forEachLine { line ->
                println(line)
            }

            file.delete()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "BufferedReaderForEachLine",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "row1\nrow2\nrow3\n")
        }
    }

    // MARK: - useLines with empty file

    func testCodegenFileUseLinesEmptyFile() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_file_uselines_empty_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("")

            val count = file.useLines { lines ->
                lines.count()
            }
            println(count)

            file.delete()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FileUseLinesEmpty",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "0\n")
        }
    }
}
