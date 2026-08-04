@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

private func runCollectionPlusAssignCodegenPipeline(
    inputPath: String,
    moduleName: String,
    outputPath: String
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: .executable,
        target: defaultTargetTriple()
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    try CodegenPhase().run(ctx)
    return ctx
}

@Suite
struct CodegenBackendCollectionPlusAssignEdgeCasesTests {
    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCollectionPlusAssignCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenCollectionPlusAssignMutatesMutableCollections() throws {
        let source = """
        fun main() {
            val list = mutableListOf(1)
            list += 2
            list += listOf(3, 4)
            println(list)

            val set = mutableSetOf("a")
            set += "b"
            set += setOf("b", "c")
            println(set)

            val map = mutableMapOf("a" to 1)
            map += ("b" to 2)
            map += mapOf("a" to 9, "c" to 3)
            println(map)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionPlusAssignEdgeCases", expected: "[1, 2, 3, 4]\n[a, b, c]\n{a=9, b=2, c=3}\n")
    }
}
#endif
