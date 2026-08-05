@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

// STDLIB-SEQ-FN-048: Sequence.indexOf
@Suite(.serialized)
struct CodegenBackendSequenceIndexOfTests {
    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenSequenceIndexOfUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val values = sequenceOf(10, 20, 10, 30)
            println(values.indexOf(10))
            println(values.indexOf(20))
            println(values.indexOf(99))
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceIndexOfRuntime", expected: "0\n1\n-1\n")
    }
}
#endif
