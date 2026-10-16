@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2284: java.net.URI remains explicitly importable through a fresh library.
    @Test
    func testJavaNetURIExplicitImportAcrossFreshLibrary() throws {
        let artifactPath = try testStdlibArtifactPath()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-java-net-uri-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = """
        import java.io.File
        import java.net.URI

        fun identity(value: URI): URI = value

        fun main() {
            println(identity(URI("file:///tmp/example.txt")).toString())
            println(File("file-control.txt").path)
        }
        """
        let input = directory.appendingPathComponent("Main.kt")
        try source.write(to: input, atomically: true, encoding: .utf8)

        for optimization in [OptimizationLevel.O0, .O2] {
            let output = directory.appendingPathComponent("uri-\(optimization)").path
            let context = try runCodegenPipeline(
                inputPath: input.path,
                moduleName: "JavaNetURI\(optimization)",
                emit: .object,
                outputPath: output,
                optLevel: optimization,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: artifactPath
            )
            try assertNoDiagnosticErrors(context)
            #expect(context.generatedObjectPath != nil)
        }
    }
}
