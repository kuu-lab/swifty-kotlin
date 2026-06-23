@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-030: kotlin.io common - useLines / forEachLine codegen tests
extension CodegenBackendIntegrationTests {

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

        try assertKotlinOutput(source, moduleName: "FileUseLines", expected: "3\nalpha\nbeta\ngamma\n")
    }

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

        try assertKotlinOutput(source, moduleName: "FileForEachLine", expected: "one\ntwo\nthree\n")
    }

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

        try assertKotlinOutput(source, moduleName: "BufferedReaderUseLines", expected: "p\nq\nr\n")
    }

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

        try assertKotlinOutput(source, moduleName: "BufferedReaderForEachLine", expected: "row1\nrow2\nrow3\n")
    }

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

        try assertKotlinOutput(source, moduleName: "FileUseLinesEmpty", expected: "0\n")
    }
}

