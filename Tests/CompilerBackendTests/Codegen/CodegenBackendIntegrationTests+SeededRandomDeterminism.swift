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

@Suite
struct CodegenBackendSeededRandomDeterminismTests {

    @Test
    func testCodegenSeededRandomCollectionAndRangeHelpersAreDeterministic() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val r1 = Random(7)
            val r2 = Random(7)

            val list1 = listOf(1, 2, 3, 4, 5).shuffled(r1)
            val list2 = listOf(1, 2, 3, 4, 5).shuffled(r2)
            println(list1 == list2)

            val seq1 = sequenceOf(1, 2, 3, 4, 5).shuffled(r1).toList()
            val seq2 = sequenceOf(1, 2, 3, 4, 5).shuffled(r2).toList()
            println(seq1 == seq2)

            val range1 = (1..100).random(r1)
            val range2 = (1..100).random(r2)
            println(range1 == range2)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SeededRandomDeterminism",
            expected:
                """
                true
                true
                true
                """ + "\n"
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
}
#endif
