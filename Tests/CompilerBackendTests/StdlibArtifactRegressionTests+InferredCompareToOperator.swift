@testable import CompilerCore
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: [true, false], [0, 2])
    func testInferredCompareToOperatorThroughSourceAndFreshArtifact(
        fromSource: Bool,
        optimization: Int
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let input = repoRoot.appendingPathComponent(
            "Scripts/diff_cases/compareto_extension_inferred_return.kt"
        ).path
        let output = directory.appendingPathComponent("compareto-extension-inferred-return").path
        let options = CompilerOptions(
            moduleName: "InferredCompareToOperator",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: fromSource,
            stdlibLibraryPath: artifactPath,
            allowDefaultStdlibLibrary: false
        )

        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == "OK\nOK\ntrue\ntrue\n42\n")
    }
}
