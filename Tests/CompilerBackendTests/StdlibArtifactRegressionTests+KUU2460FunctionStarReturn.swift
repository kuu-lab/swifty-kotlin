@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2460: a star-projected FunctionN result supplies its readable upper
    /// bound to lambda inference while star-projected inputs remain rejected.
    @Test(arguments: [false, true], [0, 2])
    func testKUU2460StarProjectedFunctionReturn(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let fixtureRoot = repositoryRoot
            .appendingPathComponent("Tests/CompilerBackendTests/Fixtures/KUU-2460")
        let output = directory.appendingPathComponent("positive").path
        let result = makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "KUU2460_Positive",
            inputs: ["lambdaWithStarReturn.kt", "minimal.kt", "minimalAndControlsRunner.kt"]
                .map { fixtureRoot.appendingPathComponent($0).path },
            outputPath: output,
            emit: .executable,
            target: CompilerTestSupport.defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: fromSource,
            stdlibLibraryPath: artifactPath,
            allowDefaultStdlibLibrary: false
        ))
        try assertCompilationSucceeded(result, context: "KUU-2460 positive fixtures compilation")

        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "Execution stderr: \(execution.stderr)")
        #expect(execution.stdout == "OK\n")
        #expect(execution.stderr.isEmpty)
    }

    @Test(arguments: [false, true], [0, 2])
    func testKUU2460RejectsIncompatibleProjectedFunctionInput(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let input = repositoryRoot
            .appendingPathComponent("Tests/CompilerBackendTests/Fixtures/KUU-2460/negativeLambdaParameter.kt").path
        let output = directory.appendingPathComponent("negative").path
        let result = makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "KUU2460Negative",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: CompilerTestSupport.defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: fromSource,
            stdlibLibraryPath: artifactPath,
            allowDefaultStdlibLibrary: false
        ))

        #expect(result.exitCode != 0)
        #expect(result.diagnostics.contains { $0.severity == .error }, "Expected the incompatible lambda input to be rejected")
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
