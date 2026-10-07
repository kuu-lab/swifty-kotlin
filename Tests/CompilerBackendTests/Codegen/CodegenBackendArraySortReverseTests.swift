#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing
import TestStdlibCache

@Suite
struct CodegenBackendArraySortReverseTests {
    // Expected output comes from Kotlin/JVM 2.4.20 on the shared diff case.
    private static let expected = """
    [a, b, c]
    [c, b, a]
    [c, a, b]
    [b, a, c]
    [c, b, a]
    [z, a, b, c, y]
    [a, z, b, c, y]
    [a, z, b, c, y]
    [a, z, b, c, y]
    [c, a, b]
    [a, d, bb, cc]
    [a, d, bb, cc]
    [a, d, bb, cc]
    [3, 2, 1]
    []
    []
    [x]
    invalid range
    negative index
    large index
    [2, 1, 3]
    [3, 1, 2]
    [3, 2, 1]
    [2, 1, 3]
    [2, 1, 3]
    [3, 1, 2]
    [3, 2, 1]
    [2, 1, 3]
    [2, 1, 3]
    [3, 1, 2]
    [3, 2, 1]
    [2, 1, 3]
    [2, 1, 3]
    [3, 1, 2]
    [3, 2, 1]
    [2, 1, 3]
    [b, a, c]
    [c, a, b]
    [c, b, a]
    [b, a, c]
    [2.0, 1.0, 3.0]
    [3.0, 1.0, 2.0]
    [3.0, 2.0, 1.0]
    [2.0, 1.0, 3.0]
    [2.0, 1.0, 3.0]
    [3.0, 1.0, 2.0]
    [3.0, 2.0, 1.0]
    [2.0, 1.0, 3.0]
    [false, false, true]
    [true, false, false]
    [false, false, true]
    [2, 1, 3]
    [3, 1, 2]
    [3, 2, 1]
    [2, 1, 3]
    [2, 1, 3]
    [3, 1, 2]
    [3, 2, 1]
    [2, 1, 3]
    [2, 1, 3]
    [3, 1, 2]
    [3, 2, 1]
    [2, 1, 3]
    [2, 1, 3]
    [3, 1, 2]
    [3, 2, 1]
    [2, 1, 3]
    []
    []
    [true]
    """ + "\n"

    @Test(arguments: [false, true])
    func remainingArraySortingAndReversal(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/array_sort_reverse_remaining.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "ArraySortReverse", emit: .executable,
                outputPath: outputBase, includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath, allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == Self.expected)
        }
    }
}
#endif
