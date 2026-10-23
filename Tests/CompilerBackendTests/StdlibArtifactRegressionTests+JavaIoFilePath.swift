@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-3051: File path accessors and kotlin.io.path.Path survive source and library modes.
    @Test
    func testJavaIoFilePathApisAcrossSourceAndFreshLibrary() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-file-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let missingName = "missing-\(UUID().uuidString).txt"
        let source = """
        import java.io.File
        import java.nio.file.Path as NioPath
        import kotlin.io.path.Path

        fun main() {
            println(File(".").exists())
            println(File("/").exists())
            println(File("\(missingName)").exists())
            println(File(".").isAbsolute)
            println(File("/").isAbsolute)
            val workingDirectory = java.lang.System.getProperty("user.dir")!!
            println(File("").absolutePath == workingDirectory)
            println(File(".").absolutePath == "$workingDirectory/.")
            println(File("segments//leaf/").absolutePath == "$workingDirectory/segments/leaf")
            println(File("/tmp//x/").absolutePath == "/tmp/x")
            val path: NioPath = Path("segments//leaf/")
            println(path.toString())
            println(Path("/").toFile().path)
        }
        """
        let input = directory.appendingPathComponent("Main.kt")
        try source.write(to: input, atomically: true, encoding: .utf8)

        let expected = [
            "true",
            "true",
            "false",
            "false",
            "true",
            "true",
            "true",
            "true",
            "true",
            "segments/leaf",
            "/",
        ].joined(separator: "\n") + "\n"

        for (surface, library) in [("Source", nil as String?), ("Library", artifactPath)] {
            for optimization in [OptimizationLevel.O0] {
                let output = directory.appendingPathComponent("file-path-\(surface)-\(optimization)").path
                let context = try runCodegenPipeline(
                    inputPath: input.path,
                    moduleName: "JavaIoFilePath\(surface)\(optimization)",
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
