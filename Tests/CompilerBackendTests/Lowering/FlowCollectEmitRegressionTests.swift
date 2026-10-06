@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing
import TestStdlibCache

@Suite
struct FlowCollectEmitRegressionTests {
    @Test(arguments: [false, true])
    func lexicalEmitAndNestedForwarding(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/flow_collect_lexical_emit.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { path in
            let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workDir) }
            let outputPath = workDir.appendingPathComponent("flow-collect-emit").path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "FlowCollectLexicalEmit",
                emit: .executable,
                outputPath: outputPath,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError, "Diagnostics: \(ctx.diagnostics.diagnostics)")
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
                [1, 2]
                [1, 2, 3, 4]
                [1, 2, 3, 4, 5, 6]
                [7, 8]
                [7, 8]

                """)
        }
    }
}
