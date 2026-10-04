#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendMultilineOperatorContinuationTests {
    private let pipelineHelper = CodegenBackendTestSupport()

    /// A declaration whose line ends with a binary operator continues on the next
    /// line. The parser used to end the declaration at the newline, silently
    /// dropping the continuation (or turning it into a stray top-level statement).
    @Test
    func testCodegenCompilesTopLevelDeclarationsWithTrailingOperatorContinuation() throws {
        let source = """
        val total: Int = 1 +
            (2 + 3)

        fun sum(): Int = total +
            4

        class Version(val major: Int, val minor: Int) {
            fun isAtLeast(major: Int, minor: Int): Boolean =
                this.major > major ||
                    (this.major == major && this.minor >= minor)
        }

        fun main() {
            println(total)
            println(sum())
            val v = Version(2, 1)
            println(v.isAtLeast(2, 1))
            println(v.isAtLeast(2, 2))
            println(v.isAtLeast(1, 9))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MultilineOperatorContinuation",
            expected: "6\n10\ntrue\nfalse\ntrue\n"
        )
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
