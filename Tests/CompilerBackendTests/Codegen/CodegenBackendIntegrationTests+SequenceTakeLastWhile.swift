@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendSequenceTakeLastWhileTests {
    private let pipelineHelper = CodegenBackendTestSupport(name: "codegenPipeline", testClosure: { _ in })

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

    // Candidate-only: Sequence.takeLastWhile (STDLIB-SEQ-FN-121) has no JVM kotlin-stdlib equivalent
    // (takeLastWhile is defined for List only), so this isn't verified via diff_kotlinc.sh.
    @Test
    func testCodegenSequenceTakeLastWhileHandlesPredicateEdgeCases() throws {
        let source = """
        fun main() {
            println(sequenceOf(1, 3, 4, 2, 5, 6).takeLastWhile { value -> value > 2 })
            println(sequenceOf(1, 2, 3).takeLastWhile { value -> value > 10 })
            println(sequenceOf(4, 5, 6).takeLastWhile { value -> value > 2 })
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceTakeLastWhileRuntime", expected: "[5, 6]\n[]\n[4, 5, 6]\n")
    }
}
#endif
