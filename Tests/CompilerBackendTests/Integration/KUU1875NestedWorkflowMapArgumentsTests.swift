@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct KUU1875NestedWorkflowMapArgumentsTests {
    @Test(arguments: [false, true])
    func methodArgumentsPreserveNestedMapTypes(allowDefaultStdlibLibrary: Bool) throws {
        let source = try diffCaseSource("kuu1875_nested_workflow_method_maps.kt", file: #filePath)
        let stdlibArtifactPath = allowDefaultStdlibLibrary ? try testStdlibArtifactPath() : nil
        for optLevel in [OptimizationLevel.O0, .O2] {
            try withTemporaryFile(contents: source) { inputPath in
                let outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: outputPath) }

                let context = try runCodegenPipeline(
                    inputPath: inputPath,
                    moduleName: "KUU1875NestedWorkflowMapArguments",
                    emit: .executable,
                    outputPath: outputPath,
                    optLevel: optLevel,
                    allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
                    stdlibLibraryPath: stdlibArtifactPath
                )
                let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
                #expect(errors.isEmpty, "compiler errors: \(errors.map(\.message).joined(separator: "; "))")
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: outputPath, arguments: [])
                #expect(result.exitCode == 0, "stderr: \(result.stderr)")
                #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "A\n")
            }
        }
    }
}
