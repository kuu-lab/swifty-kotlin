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
struct CodegenBackendSequenceTakeLastTests {
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

    // Candidate-only: Sequence.takeLast (STDLIB-SEQ-FN-120) has no JVM kotlin-stdlib equivalent
    // (takeLast is defined for List only), so this isn't verified via diff_kotlinc.sh.
    @Test
    func testCodegenSequenceTakeLastHandlesBoundaryAndNegativeCounts() throws {
        let source = """
        fun main() {
            println(sequenceOf(1, 2, 3, 4).takeLast(2))
            println(sequenceOf(1, 2).takeLast(5))
            println(sequenceOf(1, 2).takeLast(0))
            try {
                println(sequenceOf(1, 2).takeLast(-1))
                println("missing-negative")
            } catch (e: IllegalArgumentException) {
                println("negative-takeLast")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceTakeLastRuntime", expected: "[3, 4]\n[1, 2]\n[]\nnegative-takeLast\n")
    }
}
#endif
