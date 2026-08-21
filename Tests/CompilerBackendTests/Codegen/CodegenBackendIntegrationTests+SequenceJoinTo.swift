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
struct CodegenBackendSequenceJoinToTests {

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
    func testCodegenSequenceJoinToAppendsToStringBuilder() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun main() {
            val first = StringBuilder("seed:")
            sequenceOf(1, 2, 3).joinTo(first, "|", "<", ">")
            println(first.toString())

            val second = StringBuilder()
            sequenceOf("a", "b", "c").joinTo(second)
            println(second.toString())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceJoinToRuntime",
            expected:
                """
                seed:<1|2|3>
                a, b, c
                """ + "\n"
        )
    }

    @Test
    func testCodegenSequenceJoinToDoesNotUseRuntimeHelper() throws {
        let source = """
        import kotlin.text.StringBuilder

        fun render(builder: StringBuilder): String {
            sequenceOf(1, 2, 3).joinTo(builder, "|", "<", ">")
            return builder.toString()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "SequenceJoinToKIR", emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("joinTo"))
            #expect(!callees.contains("kk_sequence_joinTo"), "Sequence.joinTo should no longer route through the retired native bridge, got: \(callees)")
            // KSP-621: the CallLowerer fallback that used to rescue unresolved
            // joinTo calls onto this runtime bridge has been removed; Sequence.joinTo
            // always binds to the bundled Kotlin source (SequenceAggregateHOF.kt).
            #expect(!callees.contains("__kk_iterable_joinTo"), "Sequence.joinTo should bind to bundled source, got: \(callees)")
        }
    }
}
#endif
