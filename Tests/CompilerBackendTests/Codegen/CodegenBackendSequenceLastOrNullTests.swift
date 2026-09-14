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
        irFlags: irFlags,
        stdlibLibraryPath: try testStdlibArtifactPath()
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
struct CodegenBackendSequenceLastOrNullTests {

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
    func testCodegenSequenceLastOrNullReturnsLastElementOrNull() throws {
        let source = """
        fun main() {
            val ints = sequenceOf(1, 2, 3)
            println(ints.lastOrNull() ?: -1)

            val emptyInts = emptySequence<Int>()
            println(emptyInts.lastOrNull() ?: -1)

            val words = sequenceOf("alpha", "beta")
            println(words.lastOrNull() ?: "missing")

            val emptyWords = emptySequence<String>()
            println(emptyWords.lastOrNull() ?: "missing")
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceLastOrNullRuntime", expected: "3\n-1\nbeta\nmissing\n")
    }

    @Test
    func testCodegenSequenceLastOrNullUsesRuntimeHelper() throws {
        let source = """
        fun render(): Int? {
            return sequenceOf(1, 2, 3).lastOrNull()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceLastOrNullKIR",
                emit: .kirDump,
                outputPath: outputBase
            )

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(
                containsKotlinCallee("lastOrNull", in: callees) && !callees.contains("kk_sequence_lastOrNull"),
                "Expected Sequence.lastOrNull to resolve through the stdlib artifact, got callees: \(callees.sorted())"
            )
        }
    }
}
#endif
