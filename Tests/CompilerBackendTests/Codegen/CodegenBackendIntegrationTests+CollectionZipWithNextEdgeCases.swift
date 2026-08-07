@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionZipWithNextEdgeCasesTests {
    private let pipelineHelper = CodegenBackendTestSupport(name: "pipelineHelper", testClosure: { _ in })

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
    func testCodegenCollectionZipWithNextOverloads() throws {
        let source = """
        fun main() {
            val values = listOf(1, 3, 6, 10)
            println(values.zipWithNext())
            println(values.zipWithNext { left, right -> right - left })
            println(listOf(1).zipWithNext())
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionZipWithNextOverloads", expected: "[(1, 3), (3, 6), (6, 10)]\n[2, 3, 4]\n[]\n")
    }
}
#endif
