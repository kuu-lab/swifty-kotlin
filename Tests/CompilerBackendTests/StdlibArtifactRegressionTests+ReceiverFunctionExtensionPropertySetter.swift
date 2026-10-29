@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2456: extension setter parameter types contextualize receiver-function lambdas.
    @Test
    func testReceiverFunctionExtensionPropertySetterLambdaAcrossStdlibSurfaces() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sourcePath = repoRoot.appendingPathComponent(
            "Scripts/diff_cases/extension_property_setter_receiver_function_lambda.kt"
        ).path
        let source = try String(contentsOfFile: sourcePath, encoding: .utf8)
        let artifactPath = try Self.buildStdlibArtifact()

        for (surface, libraryPath) in [("source", nil), ("fresh .kklib", artifactPath)] {
            for optimization in [OptimizationLevel.O0, .O2] {
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                try withTemporaryFile(contents: source) { input in
                    let options = CompilerOptions(
                        moduleName: "KUU2456_\(surface)_\(optimization.rawValue)",
                        inputs: [input],
                        outputPath: output,
                        emit: .executable,
                        target: defaultTargetTriple(),
                        optLevel: optimization,
                        includeStdlib: libraryPath == nil,
                        stdlibLibraryPath: libraryPath,
                        allowDefaultStdlibLibrary: false
                    )
                    try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
                }
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0, "\(surface) at \(optimization): \(result.stderr)")
                #expect(result.stderr.isEmpty, "\(surface) at \(optimization)")
                #expect(result.stdout == "OK\n", "\(surface) at \(optimization)")
            }
        }
    }
}
