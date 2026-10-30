@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-3740: a local anonymous object keeps its next-line body.
    @Test(arguments: [false, true], [0, 2])
    func testObjectHeaderKeepsNextLineBody(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/diff_cases/object_header_newline.kt")
        let output = directory.appendingPathComponent("object-header").path
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let result = makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "ObjectHeaderNewline",
            inputs: [fixture.path],
            outputPath: output,
            emit: .executable,
            target: CompilerTestSupport.defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: fromSource,
            stdlibLibraryPath: artifactPath,
            allowDefaultStdlibLibrary: false
        ))
        try assertCompilationSucceeded(result, context: "KUU-3740 fixture compilation")

        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "Execution stderr: \(execution.stderr)")
        #expect(execution.stdout == "multiline\nmutable\nreturned\ncomplete\ncall\n")
        #expect(execution.stderr.isEmpty)
    }
}
