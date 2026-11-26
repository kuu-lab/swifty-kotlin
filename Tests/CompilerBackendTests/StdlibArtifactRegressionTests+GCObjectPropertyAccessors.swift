@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test(arguments: [false, true])
    func testGCObjectPropertyAccessorsThroughArtifactAndSource(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = try diffCaseSource(
            "stdlib_kotlin_native_runtime_GC_GC_n.kt", file: #filePath
        )
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let expected = try String(
            contentsOf: repoRoot.appendingPathComponent(
                "Scripts/diff_cases/stdlib_kotlin_native_runtime_GC_GC_n.expected"
            ),
            encoding: .utf8
        )

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "KUU2683GCObjectPropertyAccessors",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(
                result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected,
                "GC object property output diverged (useArtifact=\(useArtifact))"
            )
        }
    }
}
