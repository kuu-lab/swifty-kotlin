#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CodegenBackendIterableSumTests {
    @Test
    func testCodegenIterableSumUsesCanonicalDiffCase() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Scripts")
            .appendingPathComponent("diff_cases")
            .appendingPathComponent("stdlib_kotlin_collections_Iterable_sum.kt")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "IterableSumRuntime",
                emit: .executable,
                outputPath: outputBase,
                allowDefaultStdlibLibrary: false
            )
            try runToLowering(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(
                normalizedStdout == ("""
                6
                9
                13
                17
                3.75
                7.75
                21
                25
                29
                33
                6.0
                6
                6
                6
                6
                0
                0.0
                0
                -2147483648
                -9223372036854775808
                0
                0
                3.0
                3.0
                4
                6
                6
                3
                123
                12
                """ + "\n")
            )
        }
    }
}
#endif
