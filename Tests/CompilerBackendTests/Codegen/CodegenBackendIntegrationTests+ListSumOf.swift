@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendListSumOfTests {
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
    func testCodegenListSumOfUsesListRuntime() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.sumOf { it * 2 })
            println(emptyList<Int>().sumOf { it * 10 })
            println(values.sumOf { it.toLong() })
            println(values.sumOf { it.toDouble() })
            println(emptyList<Int>().sumOf { it.toLong() })
            println(emptyList<Int>().sumOf { it.toDouble() })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListSumOfRuntime", expected: "12\n0\n6\n6.0\n0\n0.0\n")
    }
}
#endif
