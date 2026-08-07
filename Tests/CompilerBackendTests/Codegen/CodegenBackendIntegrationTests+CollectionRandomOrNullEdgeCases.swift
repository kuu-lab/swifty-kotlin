#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CodegenBackendCollectionRandomOrNullEdgeCasesTests {
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
    func testCodegenCollectionRandomOrNullReadsCollectionReceivers() throws {
        let source = """
        fun main() {
            println(setOf("solo").randomOrNull())
            println(emptySet<Int>().randomOrNull() == null)
            val values: Collection<Int> = setOf(7)
            println(values.randomOrNull())
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionRandomOrNullEdgeCases", expected: "solo\ntrue\n7\n")
    }
}
#endif
