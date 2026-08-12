#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceLastIndexOfTests {
    private let pipelineHelper = CodegenBackendTestSupport()

    @Test
    func testCodegenSequenceLastIndexOfReturnsFinalMatchingIndexOrMinusOne() throws {
        let source = """
        fun main() {
            val ints = sequenceOf(1, 2, 3, 2)
            println(ints.lastIndexOf(2))
            println(ints.lastIndexOf(4))

            val words = sequenceOf("alpha", "beta", "alpha")
            println(words.lastIndexOf("alpha"))
            println(words.lastIndexOf("gamma"))
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceLastIndexOfRuntime", expected: "3\n-1\n2\n-1\n")
    }

    @Test
    func testCodegenSequenceLastIndexOfUsesRuntimeHelper() throws {
        let source = """
        fun render(): Int {
            return sequenceOf(1, 2, 3, 2).lastIndexOf(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SequenceLastIndexOfKIR", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("kk_sequence_lastIndexOf"))
        }
    }

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
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }
}
#endif
