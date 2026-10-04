#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendIterableTakeTests {
    private let pipelineHelper = CodegenBackendTestSupport()

    @Test
    func testCodegenIterableTakeFamilyUsesCanonicalDiffCase() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Scripts")
            .appendingPathComponent("diff_cases")
            .appendingPathComponent("stdlib_kotlin_collections_Iterable_take.kt")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path

        try withTemporaryFile(contents: source) { path in
            let ctx = try pipelineHelper.runCodegenPipeline(
                inputPath: path,
                moduleName: "IterableTakeFamily",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == """
            take-negative:Requested element count -1 is less than zero.:0:0
            take-zero:[]:0:0
            take-empty:[]:1:0
            take-less:[1, 2]:1:2
            take-equal:[1, 2, 3]:1:3
            take-more:[1, 2, 3]:1:3
            take-nullable:[a, null, c]
            while-first-false:[1]:1:2:2
            while-all:[1, 2, 3]:1:3:3
            while-none:[]:1:1:1
            while-empty:[]:1:0:0
            while-throw:predicate failed:1:2:2

            """)
        }
    }
}
#endif
