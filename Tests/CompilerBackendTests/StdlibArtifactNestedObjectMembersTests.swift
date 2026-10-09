@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct StdlibArtifactNestedObjectMembersTests {
    /// KUU-1578: nested objects under another object are values in a qualified
    /// member chain, not zero-argument member calls. Exercise the exact
    /// MainThreadFinalizerProcessor surface through both source-injected and
    /// precompiled stdlib paths so custom getters and setters stay reachable.
    @Test(arguments: [false, true])
    func testMainThreadFinalizerProcessorMembers(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = "stdlib_kotlin_native_runtime_GC_MainThreadFinalizerProcessor_MainThreadFinalizerProcessor_n"
        let fixtureDirectory = repoRoot.appendingPathComponent("Scripts/diff_cases")
        let source = try String(
            contentsOf: fixtureDirectory.appendingPathComponent("\(fixture).kt"),
            encoding: .utf8
        )
        let expected = try String(
            contentsOf: fixtureDirectory.appendingPathComponent("\(fixture).expected.stdout"),
            encoding: .utf8
        )

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }
            let ctx = makeCompilationContext(
                inputs: [userPath], moduleName: "KUU1578NestedObjectMemberReads",
                emit: .executable, outputPath: outputBase,
                includeStdlib: !useArtifact, stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected)
        }
    }
}
