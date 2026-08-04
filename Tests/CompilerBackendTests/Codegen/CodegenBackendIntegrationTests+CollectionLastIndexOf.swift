@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionLastIndexOfTests {
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

    @Test
    func testCodegenListLastIndexOfUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val ints: List<Int> = listOf(1, 2, 3, 2)
            println(ints.lastIndexOf(2))
            println(ints.lastIndexOf(4))

            val words: List<String> = listOf("alpha", "beta", "alpha")
            println(words.lastIndexOf("alpha"))
            println(words.lastIndexOf("gamma"))
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionLastIndexOf", expected: "3\n-1\n2\n-1\n")
    }
}
#endif
