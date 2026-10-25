@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: [true, false])
    func javaClassSimpleNameSupportsPropertyAndGetter(fromSource: Bool) throws {
        let source = """
        fun main() {
            println(1.javaClass.simpleName)
            println(1.javaClass.getSimpleName())
            println(Int::class.javaPrimitiveType!!.simpleName)
        }
        """
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let optimization = try #require(OptimizationLevel(rawValue: 0))

        try withTemporaryFile(contents: source) { input in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }

            let options = CompilerOptions(
                moduleName: "KUU3081JavaClassSimpleName",
                inputs: [input],
                outputPath: output,
                emit: .executable,
                target: CompilerTestSupport.defaultTargetTriple(),
                optLevel: optimization,
                includeStdlib: fromSource,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stderr.isEmpty)
            #expect(result.stdout == "Integer\nInteger\nint\n")
        }
    }
}
