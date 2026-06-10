@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-030: kotlin.io common - PrintWriter codegen tests
extension CodegenBackendIntegrationTests {

    // MARK: - File.printWriter().use {}

    func testCodegenFilePrintWriterUse() throws {
        let source = """
        import java.io.File
        import java.io.PrintWriter

        fun main() {
            val path = "/tmp/kswiftk_pw_use_codegen.txt"
            val file = File(path)
            file.delete()

            file.printWriter().use { pw ->
                pw.print("hello")
                pw.println(" world")
                pw.println()
                pw.println("done")
            }

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
                moduleName: "FilePrintWriterUse",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                "3\nhello world\n\ndone\n"
            )
        }
    }

    func testCodegenFilePrintWriterExplicitFlushClose() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_pw_flush_codegen.txt"
            val file = File(path)
            file.delete()

            val pw = file.printWriter()
            pw.println("explicit flush and close")
            pw.flush()
            pw.close()

            println(file.readText())

            file.delete()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "FilePrintWriterExplicitFlushClose",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "explicit flush and close\n\n")
        }
    }
}
