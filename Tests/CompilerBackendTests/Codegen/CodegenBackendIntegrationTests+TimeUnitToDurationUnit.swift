// STDLIB-TIME-FN-006: End-to-end execution tests for TimeUnit.toDurationUnit().
// kk_time_unit_to_duration_unit maps a java.util.concurrent.TimeUnit ordinal to the
// matching kotlin.time.DurationUnit. DurationUnit is a source-backed bundled enum,
// so its toString() prints the entry name via the exported $enumOrdinalToName helper.
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
struct CodegenBackendTimeUnitToDurationUnitTests {

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
    func testCodegenTimeUnitToDurationUnitOrdinals() throws {
        let source = """
        import java.util.concurrent.TimeUnit
        import kotlin.time.toDurationUnit

        fun main() {
            println(TimeUnit.NANOSECONDS.toDurationUnit())
            println(TimeUnit.MICROSECONDS.toDurationUnit())
            println(TimeUnit.MILLISECONDS.toDurationUnit())
            println(TimeUnit.SECONDS.toDurationUnit())
            println(TimeUnit.MINUTES.toDurationUnit())
            println(TimeUnit.HOURS.toDurationUnit())
            println(TimeUnit.DAYS.toDurationUnit())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TimeUnitToDurationUnitOrdinals",
            expected:
                """
                NANOSECONDS
                MICROSECONDS
                MILLISECONDS
                SECONDS
                MINUTES
                HOURS
                DAYS
                """
                + "\n"
        )
    }

    @Test
    func testCodegenTimeUnitToDurationUnitFeedsToDuration() throws {
        let source = """
        import java.util.concurrent.TimeUnit
        import kotlin.time.toDurationUnit
        import kotlin.time.toDuration

        fun main() {
            val unit = TimeUnit.SECONDS.toDurationUnit()
            println(2.toDuration(unit).inWholeSeconds)
            println(500L.toDuration(TimeUnit.MILLISECONDS.toDurationUnit()).inWholeMilliseconds)
        }
        """

        try assertKotlinOutput(source, moduleName: "TimeUnitToDurationUnitFeedsToDuration", expected: "2\n500\n")
    }
}
#endif
