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
struct CodegenBackendCollectionOnEachIndexedEdgeCasesTests {
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
    func testCodegenCollectionOnEachIndexedRunsActionAndReturnsReceiver() throws {
        let source = """
        fun consume(values: List<Int>) {
            var trace = ""
            val returned = values.onEachIndexed { index, value -> trace += "$index:$value;" }
            println(trace)
            println(returned)
        }

        fun main() {
            val values = listOf(10, 20, 30)
            var localTrace = ""
            val localReturned = values.onEachIndexed { index, value -> localTrace += "$index=${value / 10};" }
            println(localTrace)
            println(localReturned)
            consume(values)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionOnEachIndexedEdgeCases", expected: "0=1;1=2;2=3;\n[10, 20, 30]\n0:10;1:20;2:30;\n[10, 20, 30]\n")
    }
}
#endif
