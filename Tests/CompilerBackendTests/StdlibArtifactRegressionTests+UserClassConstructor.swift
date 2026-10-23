@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-3012: a user class with an implicit Any superclass must link when
    /// the stdlib is imported from a serialized artifact.
    @Test(arguments: [true, false])
    func testUserDefinedPrimaryConstructorLinksWithAndWithoutStdlibArtifact(
        useArtifact: Bool
    ) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = """
        class A(val v: Int)
        fun main() { println(A(3).v) }
        """

        try withTemporaryFile(contents: source) { inputPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }

            let options = CompilerOptions(
                moduleName: "KUU3012UserClassConstructor",
                inputs: [inputPath],
                outputPath: outputPath,
                emit: .executable,
                target: CompilerTestSupport.defaultTargetTriple(),
                optLevel: .O0,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(
                makeTestDriver().runForTesting(options: options),
                context: useArtifact ? "Artifact-backed user constructor" : "Source-backed user constructor"
            )

            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stderr.isEmpty)
            #expect(result.stdout == "3\n")
        }
    }
}
