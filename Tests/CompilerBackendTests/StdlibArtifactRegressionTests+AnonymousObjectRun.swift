@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2043: an inapplicable outer member must not hide stdlib run.
    @Test(arguments: [false, true], [0, 2])
    func testAnonymousObjectOuterRun(useArtifact: Bool, optimization: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let artifact = useArtifact ? try Self.buildStdlibArtifact() : nil
        let cases = [
            ("anonymous_object_outer_run.kt", "1\n1\n2\n"),
            ("anonymous_object_outer_run_controls.kt", "1\n1\n2\n1\n1\n2\n3\n4\n5\n4\n7\n21\n6\n"),
        ]
        for (file, expected) in cases {
            let source = try diffCaseSource(file, file: #filePath)
            try withTemporaryFile(contents: source) { path in
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let ctx = try runCodegenPipeline(
                    inputPath: path, moduleName: "AnonymousObjectOuterRun", outputPath: output,
                    optLevel: optLevel, allowDefaultStdlibLibrary: false, stdlibLibraryPath: artifact
                )
                try LinkPhase().run(ctx)
                let result = try CommandRunner.run(executable: output, arguments: [], timeout: 10)
                #expect(result.exitCode == 0)
                #expect(result.stdout == expected, "\(file), artifact: \(useArtifact), optimization: \(optimization)")
                #expect(result.stderr.isEmpty)
            }
        }
    }
}
