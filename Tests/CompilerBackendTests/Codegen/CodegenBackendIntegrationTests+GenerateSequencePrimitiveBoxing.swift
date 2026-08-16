#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// BUG-187 (KSP-500): `generateSequence` seed/next-function results and
/// `sequence { yield(value) }` builder arguments were not boxed for primitive
/// element types, so `Char`/`Double`/`Int`/`Boolean`/enum values leaked as raw
/// ordinal/code-point integers and `Double` null terminators were mis-boxed as
/// `-0.0`, producing infinite sequences.

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
struct CodegenBackendGenerateSequencePrimitiveBoxingTests {

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
    func testGenerateSequenceCharBoxesSeedAndNullableNextResult() throws {
        let source = """
        fun main() {
            println(generateSequence('A') { null }.toList())
            println(generateSequence('A') { if (it == 'A') 'B' else null }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceChar",
            expected:
                """
                [A]
                [A, B]
                """
                + "\n"
        )
    }

    @Test
    func testGenerateSequenceDoubleBoxesNullableNextResult() throws {
        let source = """
        fun main() {
            println(generateSequence(1.5) { if (it == 1.5) 2.5 else null }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceDouble",
            expected: "[1.5, 2.5]\n"
        )
    }

    @Test
    func testGenerateSequenceIntBoxesNullableNextResult() throws {
        let source = """
        fun main() {
            println(generateSequence(1) { if (it < 3) it + 1 else null }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceInt",
            expected: "[1, 2, 3]\n"
        )
    }

    @Test
    func testGenerateSequenceZeroSeedIsNotNull() throws {
        let source = """
        fun main() {
            println(generateSequence(0) { null }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceZero",
            expected: "[0]\n"
        )
    }

    @Test
    func testGenerateSequenceEnumBoxesSeedAndNullableNextResult() throws {
        let source = """
        enum class Direction { NORTH }

        fun main() {
            println(generateSequence(Direction.NORTH) { null }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceEnum",
            expected: "[NORTH]\n"
        )
    }

    @Test
    func testGenerateSequenceNoArgTerminatesOnNull() throws {
        let source = """
        fun main() {
            println(generateSequence { null }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenerateSequenceNoArg",
            expected: "[]\n"
        )
    }

    @Test
    func testSequenceBuilderYieldsPrimitiveCharsAndDoubles() throws {
        let source = """
        fun main() {
            println(sequence { yield('X'); yield('Y') }.toList())
            println(sequence { yield(1.5); yield(2.5) }.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceBuilderPrimitives",
            expected:
                """
                [X, Y]
                [1.5, 2.5]
                """
                + "\n"
        )
    }
}
#endif
