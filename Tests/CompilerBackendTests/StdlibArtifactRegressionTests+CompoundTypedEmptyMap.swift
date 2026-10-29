@testable import CompilerCore
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: [false, true], [0, 2])
    func testCompoundTypedEmptyMapThroughSourceAndFreshArtifact(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for (name, expected) in [
            ("compound_typed_empty_map", "1\n"),
            ("compound_typed_empty_map_properties", "2\n1\n2\n"),
        ] {
            let output = directory.appendingPathComponent(name).path
            let options = CompilerOptions(
                moduleName: "CompoundTypedEmptyMap",
                inputs: [repoRoot.appendingPathComponent("Scripts/diff_cases/\(name).kt").path],
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
            #expect(result.stdout == expected, "Unexpected output for \(name)")
        }
    }
}
