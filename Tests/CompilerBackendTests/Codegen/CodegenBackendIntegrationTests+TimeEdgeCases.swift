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

@Suite
struct CodegenBackendTimeEdgeCasesTests {

    @Test
    func testCodegenCompilesTimeEdgeCases() throws {
        let source = """
        import kotlin.time.*
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val measured = measureTimedValue {
                40 + 2
            }
            println(measured.value)
            println(measured.duration.isPositive())

            val negative = (-5).seconds
            println(negative.inWholeSeconds)
            println(negative.isNegative())

            val epoch = Instant.fromEpochMilliseconds(0L)
            val later = epoch + 1500.milliseconds
            println(later.epochSeconds)
            println(later.nanosecondsOfSecond)

            val earlier = later - 2.seconds
            println(earlier.epochSeconds)
            println(earlier.nanosecondsOfSecond)

            println(epoch.isDistantPast)
            println(epoch.isDistantFuture)
            println(Instant.fromEpochMilliseconds(-3217862419200001L).isDistantPast)
            println(Instant.fromEpochMilliseconds(-3217862419200000L).isDistantPast)
            println(Instant.fromEpochMilliseconds(3093527980800000L).isDistantFuture)
            println(Instant.fromEpochMilliseconds(3093527980799999L).isDistantFuture)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TimeEdgeCases",
            expected:
                """
                42
                true
                -5
                true
                1
                500000000
                -1
                500000000
                false
                false
                true
                false
                true
                false
                """ + "\n"
        )
    }
}
#endif
