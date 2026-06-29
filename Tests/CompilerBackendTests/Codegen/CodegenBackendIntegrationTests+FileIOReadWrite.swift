@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// STDLIB-030: kotlin.io common - File read/write codegen tests
extension CodegenBackendIntegrationTests {

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

        try assertKotlinOutput(source, moduleName: "FileWriteReadText", expected: "hello world\n")
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

        try assertKotlinOutput(source, moduleName: "FileAppendText", expected: "line1\nline2\n")
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

        try assertKotlinOutput(source, moduleName: "FileReadLines", expected: "3\nalpha\nbeta\ngamma\n")
    }
}

