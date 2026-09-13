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
}
#endif
