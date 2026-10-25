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

    /// KUU-3364: the Java-facing URI, Path, and Charset APIs survive stdlib packaging.
    @Test
    func testJavaNetURIPathAndCharsetMembersAcrossSourceAndFreshLibrary() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-java-platform-apis-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = """
        import java.net.URI
        import java.nio.charset.Charset
        import java.nio.file.Files
        import java.nio.file.Path
        import java.nio.file.Paths

        fun main() {
            val uri = URI("https://user@example.com:8443/a/b/c?q=1#fragment")
            println(uri.scheme)
            println(uri.userInfo)
            println(uri.host)
            println(uri.port)
            println(uri.path)
            println(uri.query)
            println(uri.fragment)
            println(uri.resolve("../next?x=2"))
            println(URI.create("https://example.com/a/../b").normalize())

            val path = Paths.get("/tmp/folder/../note.txt")
            println(path.fileName)
            println(path.parent)
            println(path.isAbsolute)
            println(path.normalize())
            println(Path.of("alpha", "beta"))
            println(Path.of("alpha/beta").resolve("../gamma").normalize())
            println(Path.of("alpha/beta").relativize(Path.of("alpha/gamma")))
            println(Files.exists(Paths.get(".")))

            val available = Charset.availableCharsets()
            println(available.firstKey())
            println(available["UTF-8"]?.name())
            println(available["UTF-8"]?.contains(Charset.forName("US-ASCII")))
            println(Charset.isSupported("utf8"))
            println(Charset.forName("unknown-charset", Charset.defaultCharset())?.name())
        }
        """
        let input = directory.appendingPathComponent("Main.kt")
        try source.write(to: input, atomically: true, encoding: .utf8)
        let expected = """
        https
        user
        example.com
        8443
        /a/b/c
        q=1
        fragment
        https://user@example.com:8443/a/next?x=2
        https://example.com/b
        note.txt
        /tmp/folder/..
        true
        /tmp/note.txt
        alpha/beta
        alpha/gamma
        ../gamma
        true
        ISO-8859-1
        UTF-8
        true
        true
        UTF-8
        """ + "\n"

        for (surface, library) in [("Source", nil as String?), ("Library", artifactPath)] {
            let output = directory.appendingPathComponent("platform-apis-\(surface)").path
            let context = try runCodegenPipeline(
                inputPath: input.path,
                moduleName: "JavaPlatformApis\(surface)",
                outputPath: output,
                optLevel: .O0,
                allowDefaultStdlibLibrary: false,
                prepareTestStdlibCache: false,
                stdlibLibraryPath: library
            )
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)
            let result = try CommandRunner.run(
                executable: output,
                arguments: [],
                currentDirectoryPath: directory.path
            )
            #expect(result.exitCode == 0, "\(surface): \(result.stderr)")
            #expect(result.stderr.isEmpty)
            #expect(result.stdout == expected, "\(surface)")
        }
    }
}
