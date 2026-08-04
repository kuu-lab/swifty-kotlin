#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendListSortedByDescendingTests {
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
    func testCodegenListSortedByDescendingUsesPrimitiveAndObjectSelectorPaths() throws {
        let source = """
        fun main() {
            println(listOf(21, 12, 22, 11).sortedByDescending { it % 10 })
            println(listOf("b", "a", "c").sortedByDescending { it })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListSortedByDescendingRuntime", expected: "[12, 22, 21, 11]\n[c, b, a]\n")
    }
}
#endif
