@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: [
        "Files.readAllBytes(\"input.txt\")",
        "Paths.get(42)",
        "Paths.get(\"input.txt\", 42)",
        "Files.readString(Paths.get(\"input.txt\"))",
    ])
    func testJavaNioFilesLibraryRejectsUnsupportedCalls(expression: String) throws {
        let artifactPath = try Self.buildStdlibArtifact()
        try withTemporaryFile(contents: """
        import java.nio.file.Files
        import java.nio.file.Paths
        fun main() { println(\(expression)) }
        """) { path in
            let context = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            do {
                try runSema(context)
            } catch {
                // Inspect the diagnostics produced for the imported signatures.
            }
            #expect(context.diagnostics.hasError, "Expected rejection of \(expression)")
        }
    }

    /// KUU-2015: public Path/Paths/Files signatures and byte I/O survive metadata.
    @Test
    func testJavaNioFilesAcrossSourceAndFreshLibrary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-nio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let parts = directory.appendingPathComponent("parts")
        try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
        try Data("hello\n".utf8).write(to: directory.appendingPathComponent("input.txt"))
        try Data("segments\n".utf8).write(to: parts.appendingPathComponent("input.txt"))
        try Data().write(to: directory.appendingPathComponent("empty.txt"))
        try Data([0, 127, 128, 255]).write(to: directory.appendingPathComponent("binary.dat"))
        try Data((0 ..< 16_385).map { UInt8(truncatingIfNeeded: $0) })
            .write(to: directory.appendingPathComponent("large.dat"))

        let source = """
        import java.io.IOException
        import java.nio.file.Files
        import java.nio.file.Path
        import java.nio.file.Paths

        fun read(path: Path): ByteArray = Files.readAllBytes(path)

        // Pinned Klox Main.kt file-read statement, kept verbatim:
        // https://github.com/negset/klox/blob/d250b3cefe54d556d192a32cc47c6749804a05af/src/com/negset/klox/Main.kt
        fun runFile(path: String): ByteArray {
            val bytes = Files.readAllBytes(Paths.get(path))
            return bytes
        }

        fun main() {
            println(String(Files.readAllBytes(Paths.get("input.txt"))).trim())
            println(String(runFile("input.txt")).trim())
            println(Files.exists(Paths.get("input.txt")))
            println(Files.exists(Paths.get("parts")))
            println(Files.exists(Paths.get("missing.txt")))
            val path: Path = Paths.get("parts", "", "input.txt")
            println(String(read(path)).trim())
            println(read(Paths.get("empty.txt")).size)
            val bytes: ByteArray = read(Paths.get("binary.dat"))
            println(bytes.joinToString(","))
            bytes[0] = 42
            println(read(Paths.get("binary.dat"))[0])
            val large = read(Paths.get("large.dat"))
            println(large.size)
            println(large[8191])
            println(large[8192])
            println(large[16384])
            println(Paths.get("parts//", "/input.txt/").toString())
            println(Paths.get("", "parts", "input.txt") == path)
            println(Paths.get("/").toString())
            println(Paths.get("").toString().length)
            try {
                read(Paths.get("missing.txt"))
                println("missing: not thrown")
            } catch (failure: IOException) {
                println("missing: IOException")
            }
            try {
                read(Paths.get("missing.txt"))
                println("missing: not thrown")
            } catch (failure: Exception) {
                println("missing: Exception")
            }
        }
        """
        let input = directory.appendingPathComponent("Main.kt")
        try source.write(to: input, atomically: true, encoding: .utf8)
        let expected = "hello\nhello\ntrue\ntrue\nfalse\nsegments\n0\n0,127,-128,-1\n0\n16385\n-1\n0\n0\nparts/input.txt\ntrue\n/\n0\nmissing: IOException\nmissing: Exception\n"
        let artifactPath = try Self.buildStdlibArtifact()
        for (surface, library) in [("Source", nil as String?), ("Library", artifactPath)] {
            for optimization in [OptimizationLevel.O0, .O2] {
                let output = directory.appendingPathComponent("nio-\(surface)-\(optimization)").path
                let context = try runCodegenPipeline(
                    inputPath: input.path,
                    moduleName: "JavaNioFiles\(surface)\(optimization)",
                    outputPath: output,
                    optLevel: optimization,
                    allowDefaultStdlibLibrary: false,
                    stdlibLibraryPath: library
                )
                try assertNoDiagnosticErrors(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(
                    executable: output,
                    arguments: [],
                    currentDirectoryPath: directory.path
                )
                #expect(result.exitCode == 0, "\(surface) \(optimization): \(result.stderr)")
                #expect(result.stderr.isEmpty)
                #expect(result.stdout == expected, "\(surface) \(optimization)")
            }
        }
    }
}
