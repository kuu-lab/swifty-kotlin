@testable import CompilerCore
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: [0, 2])
    func testBareObjectCompoundAssignThroughFreshArtifact(optimization: Int) throws {
        try assertBareObjectCompoundAssign(fromSource: false, optimization: optimization)
    }

    @Test
    func testBareObjectCompoundAssignThroughSource() throws {
        try assertBareObjectCompoundAssign(fromSource: true, optimization: 0)
    }

    private func assertBareObjectCompoundAssign(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = repoRoot.appendingPathComponent("Scripts/diff_cases/bare_object_compound_assign.kt").path
        let output = directory.appendingPathComponent("bare-object-compound-assign").path
        let options = CompilerOptions(
            moduleName: "BareObjectCompoundAssign",
            inputs: [source],
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
        #expect(result.stdout == "OK\nOK\n")
    }
}
