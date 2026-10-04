@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendSequenceToSetTests {
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
                emit: EmitMode.executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenSequenceToSetUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("sequence_toset.kt")

        try assertKotlinOutput(source, moduleName: "SequenceToSetRuntime", expected: "[3, 1, 2]\ntrue\nfalse\n[]\n")
    }
}
#endif
