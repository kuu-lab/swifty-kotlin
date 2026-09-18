#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

// STDLIB-030: kotlin.io common - File read/write codegen tests
//
// CLEANUP-STUB-107 removed java.io.File's writeText/readText/appendText/delete
// synthetic members, so this suite's original write+read and append+read
// cases (which depended entirely on those dead members) were deleted. Only
// `testCodegenFileReadLines` survives: `File.readLines()` is a Kotlin-source
// extension (Stdlib/kotlin/io/FileIO.kt) that calls the runtime's
// `__kk_file_readText` directly rather than the removed `readText()` member,
// so it remains alive. Its setup now writes the fixture file from the host
// side (matching the pattern already used elsewhere in this test target)
// since `File.delete()`/`writeText()` are no longer available from Kotlin.
@Suite
struct CodegenBackendFileIOReadWriteTests {

    @Test func testCodegenFileReadLines() throws {
        let tmpPath = "/tmp/kswiftk_file_read_lines_codegen.txt"
        try "alpha\nbeta\ngamma".write(toFile: tmpPath, atomically: true, encoding: .utf8)

        let source = """
        import java.io.File

        fun main() {
            val file = File("\(tmpPath)")

            val lines = file.readLines()
            println(lines.size)
            for (line in lines) {
                println(line)
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "FileReadLines", expected: "3\nalpha\nbeta\ngamma\n")
    }

    // KUU-640: File.readLines / forEachLine / useLines must treat LF, CR, and
    // CRLF as terminators and must not leave `\r` in the line.
    // assertKotlinOutput normalizes `\r\n` in stdout, so leftover CR would be
    // hidden by `println(line)`; emit length and a visible CR marker instead.
    @Test func testCodegenFileReadLinesMixedLineEndings() throws {
        let mixedPath = "/tmp/kswiftk_file_read_lines_crlf_codegen.txt"
        let crOnlyPath = "/tmp/kswiftk_file_read_lines_cr_only_codegen.txt"
        try "a\r\nb\rc\n".write(toFile: mixedPath, atomically: true, encoding: .utf8)
        try "x\ry".write(toFile: crOnlyPath, atomically: true, encoding: .utf8)

        let source = """
        import java.io.File

        fun dump(file: File) {
            val lines = file.readLines()
            println(lines.size)
            for (line in lines) {
                println(line.length)
                println(line.replace("\\r", "<CR>"))
            }
            file.forEachLine { line ->
                println(line.replace("\\r", "<CR>"))
            }
            file.useLines { ls ->
                println(ls.size)
                for (line in ls) {
                    println(line.replace("\\r", "<CR>"))
                }
            }
        }

        fun main() {
            dump(File("\(mixedPath)"))
            dump(File("\(crOnlyPath)"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FileReadLinesCRLF",
            expected: """
            3
            1
            a
            1
            b
            1
            c
            a
            b
            c
            3
            a
            b
            c
            2
            1
            x
            1
            y
            x
            y
            2
            x
            y
            """
            + "\n"
        )
    }
}
#endif
