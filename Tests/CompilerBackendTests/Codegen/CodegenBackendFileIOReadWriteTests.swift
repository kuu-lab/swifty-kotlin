#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

// STDLIB-030: kotlin.io common - File read/write codegen tests
//
// CLEANUP-STUB-107 removed java.io.File's writeText/appendText/delete synthetic
// members. File.readText() is now a Kotlin-source extension in
// Stdlib/kotlin/io/FileIO.kt and routes through the runtime readText bridge.
// Fixture files are written from the host side because File.writeText() and
// File.delete() remain outside the supported surface.
@Suite
struct CodegenBackendFileIOReadWriteTests {

    @Test func testCodegenFileReadTextSourceAndLibraryPaths() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
        let readTextPath = tempDirectory.appendingPathComponent("kswiftk_read_text_\(UUID().uuidString).txt").path
        let lineEndingsPath = tempDirectory.appendingPathComponent("kswiftk_read_text_lines_\(UUID().uuidString).txt").path
        let emptyPath = tempDirectory.appendingPathComponent("kswiftk_read_text_empty_\(UUID().uuidString).txt").path
        let latin1Path = tempDirectory.appendingPathComponent("kswiftk_read_text_latin1_\(UUID().uuidString).txt").path
        let missingPath = tempDirectory.appendingPathComponent("kswiftk_read_text_missing_\(UUID().uuidString).txt").path

        try "hello\n".write(toFile: readTextPath, atomically: true, encoding: .utf8)
        try "café\r\nend\n".write(toFile: lineEndingsPath, atomically: true, encoding: .utf8)
        try Data().write(to: URL(fileURLWithPath: emptyPath))
        try Data([0x63, 0x61, 0x66, 0xe9]).write(to: URL(fileURLWithPath: latin1Path))

        let source = """
        import java.io.File

        fun main() {
            println(File("\(readTextPath)").readText().trim())
            val text = File("\(lineEndingsPath)").readText()
            println(text.trim())
            println(text.replace("\\r", "<CR>"))
            println(File("\(emptyPath)").readText().length)
            println(File("\(latin1Path)").readText(charset = Charsets.ISO_8859_1))
            try {
                File("\(missingPath)").readText()
                println("missing: not thrown")
            } catch (failure: FileSystemException) {
                println("missing: caught")
            }
        }
        """
        let expected = "hello\ncafé\nend\ncafé<CR>\nend\n\n0\ncafé\nmissing: caught\n"
        let stdlibModes: [(name: String, allowDefaultStdlibLibrary: Bool)] = [
            ("Source", false),
            ("Library", true),
        ]
        let optimizationLevels: [(name: String, value: OptimizationLevel)] = [
            ("O0", .O0),
            ("O2", .O2),
        ]

        for mode in stdlibModes {
            for optimization in optimizationLevels {
                try assertKotlinOutput(
                    source,
                    moduleName: "FileReadText\(mode.name)\(optimization.name)",
                    expected: expected,
                    optLevel: optimization.value,
                    allowDefaultStdlibLibrary: mode.allowDefaultStdlibLibrary
                )
            }
        }
    }

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
