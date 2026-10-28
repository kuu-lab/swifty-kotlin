@testable import CompilerCore
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: [true, false], [0, 2])
    func testNullablePrimitiveCompareToOperatorThroughSourceAndFreshArtifact(
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
            "Scripts/diff_cases/kuu_2292_nullable_primitive_compareto.kt"
        ).path
        let output = directory.appendingPathComponent("nullable-primitive-compareto").path
        let options = CompilerOptions(
            moduleName: "NullablePrimitiveCompareToOperator",
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
        #expect(result.stdout == "OK\ntrue:1\n-1:1\ntrue:1\ntrue\n")
    }
}
