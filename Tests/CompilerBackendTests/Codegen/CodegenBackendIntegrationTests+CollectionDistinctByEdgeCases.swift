@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite(.serialized)
struct CodegenBackendCollectionDistinctByEdgeCasesTests {
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
    func testCodegenCollectionDistinctByEdgeCases() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3, 4, 5)
            println(values.distinctBy { it % 2 })
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionDistinctByEdgeCases", expected: "[1, 2]\n")
    }
}
#endif
