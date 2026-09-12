#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceTakeTests {
    private let pipelineHelper = CodegenBackendTestSupport()

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try pipelineHelper.runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test func testCodegenSequenceTakeUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("sequence_take.kt")

        try assertKotlinOutput(source, moduleName: "SequenceTakeRuntime", expected: "[1, 2]\n[1, 2]\n[]\n")
    }
}
#endif
