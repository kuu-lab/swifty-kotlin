@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
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
        allowDefaultStdlibLibrary: false
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
struct CodegenBackendExperimentalTimeEdgeCasesTests {
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
    func codegenCompilesTestTimeSource() throws {
        let source = """
        import kotlin.time.AbstractDoubleTimeSource
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.Duration.Companion.microseconds
        import kotlin.time.Duration.Companion.nanoseconds
        import kotlin.time.DurationUnit
        import kotlin.time.ExperimentalTime
        import kotlin.time.TestTimeSource

        class DoubleProbe : AbstractDoubleTimeSource(DurationUnit.MILLISECONDS) {
            private var reading = 0.0

            protected override fun read(): Double = reading

            fun advance(delta: Double) {
                reading += delta
            }
        }

        @OptIn(ExperimentalTime::class)
        fun main() {
            val source = TestTimeSource()
            val mark1 = source.markNow()

            source += 5.milliseconds
            val mark2 = source.markNow()

            source += 10.milliseconds
            val mark3 = source.markNow()

            // mark differences are deterministic
            println((mark2 - mark1).inWholeMilliseconds)
            println((mark3 - mark2).inWholeMilliseconds)
            println((mark3 - mark1).inWholeMilliseconds)

            // mark ordering is deterministic
            println(mark1.compareTo(mark2) < 0)
            println(mark2.compareTo(mark3) < 0)

            // advancing by nanoseconds
            source += 500.nanoseconds
            val mark4 = source.markNow()
            println((mark4 - mark3).inWholeNanoseconds)

            // Negative advances and source-backed mark arithmetic
            source += (-250L).microseconds
            val negativeMark = source.markNow()
            println((negativeMark - mark4).inWholeNanoseconds)

            // Both finite-boundary overflow directions must throw
            val positiveOverflow = TestTimeSource()
            positiveOverflow += (Long.MAX_VALUE - 1L).nanoseconds
            positiveOverflow += 1.nanoseconds
            try {
                positiveOverflow += 1.nanoseconds
                println("missing-positive-overflow")
            } catch (e: IllegalStateException) {
                println("positive-overflow")
            }

            val negativeOverflow = TestTimeSource()
            negativeOverflow += (-9223372036854775807L).nanoseconds
            negativeOverflow += (-1L).nanoseconds
            try {
                negativeOverflow += (-1L).nanoseconds
                println("missing-negative-overflow")
            } catch (e: IllegalStateException) {
                println("negative-overflow")
            }

            val doubleSource = DoubleProbe()
            val doubleMark1 = doubleSource.markNow()
            doubleSource.advance(1.25)
            val doubleMark2 = doubleSource.markNow()
            println((doubleMark2 - doubleMark1).inWholeNanoseconds)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TestTimeSourceEdgeCases",
            expected:
                """
                5
                10
                15
                true
                true
                500
                -250000
                positive-overflow
                negative-overflow
                1250000
                """
                + "\n"
        )
    }

    @Test
    func codegenCompilesExperimentalTimeEdgeCases() throws {
        let source = """
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.ExperimentalTime
        import kotlin.time.*

        @OptIn(ExperimentalTime::class)
        fun main() {
            val start = TimeSource.Monotonic.markNow()
            val future = start + 5.milliseconds
            val past = future - 10.milliseconds

            println((future - start).inWholeMilliseconds)
            println((future - past).inWholeMilliseconds)
            // hasNotPassedNow() is timing-sensitive; only check past.hasPassedNow()
            println(past.hasPassedNow())
            val clock = TimeSource.Monotonic.asClock(Instant.fromEpochMilliseconds(0L))
            println(clock.now().epochSeconds >= 0L)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ExperimentalTimeEdgeCases",
            expected:
                """
                5
                10
                true
                true
                """
                + "\n"
        )
    }
}
#endif
