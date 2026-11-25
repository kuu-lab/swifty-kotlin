#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendFileUseLinesForEachLineTests {

    @Test
    func testCodegenFileUseLines() throws {
        let tmpPath = "/tmp/kswiftk_file_uselines_codegen.txt"
        try "alpha\nbeta\ngamma".write(toFile: tmpPath, atomically: true, encoding: .utf8)

        let source = """
        import java.io.File

        fun main() {
            val file = File("\(tmpPath)")

            val count = file.useLines { lines ->
                lines.count()
            }
            println(count)

            file.useLines { lines ->
                lines.forEach { line -> println(line) }
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "FileUseLines", expected: "3\nalpha\nbeta\ngamma\n")
    }

    @Test
    func testCodegenFileUseLinesListResultMemberAccess() throws {
        let tmpPath = "/tmp/kswiftk_file_uselines_list_result_codegen.txt"
        try "alpha\nbeta\ngamma".write(toFile: tmpPath, atomically: true, encoding: .utf8)

        let source = """
        import java.io.File

        fun main() {
            val file = File("\(tmpPath)")
            val collected = file.useLines { it.toList() }
            println(collected.size)
            println(collected.first())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FileUseLinesListResultMemberAccess",
            expected: "3\nalpha\n"
        )
    }

    @Test
    func testCodegenFileForEachLine() throws {
        let tmpPath = "/tmp/kswiftk_file_foreachline_codegen.txt"
        try "one\ntwo\nthree".write(toFile: tmpPath, atomically: true, encoding: .utf8)

        let source = """
        import java.io.File

        fun main() {
            val file = File("\(tmpPath)")

            file.forEachLine { line ->
                println(line)
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "FileForEachLine", expected: "one\ntwo\nthree\n")
    }

    @Test
    func testCodegenFileUseLinesEmptyFile() throws {
        let tmpPath = "/tmp/kswiftk_file_uselines_empty_codegen.txt"
        try "".write(toFile: tmpPath, atomically: true, encoding: .utf8)

        let source = """
        import java.io.File

        fun main() {
            val file = File("\(tmpPath)")

            val count = file.useLines { lines ->
                lines.count()
            }
            println(count)
        }
        """

        try assertKotlinOutput(source, moduleName: "FileUseLinesEmpty", expected: "0\n")
    }
}
#endif
