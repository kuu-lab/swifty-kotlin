@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendSequenceSubtractTests {
    private let pipelineHelper = CodegenBackendTestSupport(name: "SequenceSubtract", testClosure: { _ in })

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

    // Candidate-only: Sequence.subtract (STDLIB-SEQ-FN-115) has no JVM kotlin-stdlib equivalent
    // (subtract is an Iterable extension, and Sequence does not implement Iterable), so this
    // isn't verified via diff_kotlinc.sh.
    @Test
    func testCodegenSequenceSubtractHandlesListSetAndEmptyReceivers() throws {
        let source = """
        fun main() {
            println(sequenceOf(1, 2, 2, 3, 4).subtract(listOf(2, 4, 2)))
            println(sequenceOf("a", "b", "a", "c").subtract(setOf("a")))
            println(emptySequence<Int>().subtract(listOf(1)))
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceSubtractRuntime", expected: "[1, 3]\n[b, c]\n[]\n")
    }
}
#endif
