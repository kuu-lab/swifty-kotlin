#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

// STDLIB-030: kotlin.io common - useLines / forEachLine codegen tests
//
// CLEANUP-STUB-107 removed java.io.File's delete/writeText/bufferedReader
// synthetic members. `File.useLines`/`File.forEachLine` themselves survive
// (Kotlin-source extensions in Stdlib/kotlin/io/FileIO.kt that call the
// runtime's `__kk_file_readText` directly, not the removed `readText()`
// member), so the three File-based cases below keep their real Kotlin-side
// assertions and only swap their now-dead `file.delete(); file.writeText(...)`
// setup for a host-side fixture write. The two BufferedReader-based cases
// (`file.bufferedReader().useLines {}` / `.forEachLine {}`) were deleted
// outright: their only path to a receiver was `File.bufferedReader()`, which
// is dead, and `kotlin.io.path.Path` has no confirmed working substitute —
// `Path.useLines` was independently removed by CLEANUP-STUB-116 (see
// Tests/CompilerCoreTests/Sema/PathGenericFunctionStubRemovalTests.swift),
// and no Sema registration for `Path.bufferedReader()` could be found either.
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
