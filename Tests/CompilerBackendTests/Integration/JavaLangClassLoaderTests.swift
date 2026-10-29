import Foundation
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite(.serialized)
struct JavaLangClassLoaderTests {
    @Test(arguments: [0, 2])
    func classLoaderGetterWorksWithFreshStdlibArtifact(optimization: Int) throws {
        let library = try testStdlibArtifactPath()
        let source = """
        import java.lang.Class
        import java.lang.ClassLoader

        object ResourceOwner
        fun loader() = ResourceOwner.javaClass.classLoader
        fun nullableLoader(): ClassLoader? = loader()
        fun classToken(): Class<ResourceOwner> = ResourceOwner.javaClass
        fun assertionsEnabled(): Boolean = ResourceOwner.javaClass.desiredAssertionStatus()

        fun main() {
            println(classToken() != null)
            println(nullableLoader() != null)
            println(assertionsEnabled())
        }
        """
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: output) }

        try withTemporaryFile(contents: source) { input in
            let options = CompilerOptions(
                moduleName: "KUU2285ClassLoader",
                inputs: [input],
                outputPath: output,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                includeStdlib: false,
                stdlibLibraryPath: library,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        }

        // Fix the process policy so the desiredAssertionStatus control is deterministic.
        let result = try CommandRunner.run(
            executable: "/usr/bin/env",
            arguments: [
                "-u", "KK_ASSERTIONS_ENABLED", "-u", "KOTLIN_ASSERTIONS_ENABLED",
                "KK_ASSERTIONS_ENABLED=1", output,
            ]
        )
        #expect(result.exitCode == 0, "Unexpected exit code: \(result.stderr)")
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "true\ntrue\ntrue\n")
    }
}
