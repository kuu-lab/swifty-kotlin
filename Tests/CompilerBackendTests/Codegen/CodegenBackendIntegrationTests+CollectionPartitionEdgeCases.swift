#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func runCodegenPipeline(
    inputPath: String,
    moduleName: String,
    emit: EmitMode,
    outputPath: String,
    irFlags: [String] = []
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        irFlags: irFlags
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    if emit == .kirDump {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for dump.")
        }
        let path = outputPath + ".kir"
        let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    } else {
        try CodegenPhase().run(ctx)
    }
    return ctx
}

@Suite(.serialized)
struct CodegenBackendCollectionPartitionEdgeCasesTests {
    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
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

    @Test
    func testCodegenCollectionPartitionSplitsElementsAndHandlesEmptySources() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3, 4, 5)
            val (evens, odds) = values.partition { it % 2 == 0 }
            println(evens)
            println(odds)

            val empty = emptyList<Int>()
            val (matchingEmpty, restEmpty) = empty.partition { it > 0 }
            println(matchingEmpty.size)
            println(restEmpty.size)

            val (allMatch, noneLeft) = listOf(2, 4, 6).partition { it % 2 == 0 }
            println(allMatch)
            println(noneLeft.size)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionPartitionEdgeCases", expected: "[2, 4]\n[1, 3, 5]\n0\n0\n[2, 4, 6]\n0\n")
    }
}
#endif
