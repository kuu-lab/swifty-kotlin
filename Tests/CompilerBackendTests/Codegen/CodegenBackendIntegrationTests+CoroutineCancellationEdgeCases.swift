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
struct CodegenBackendCoroutineCancellationEdgeCasesTests {
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

    @Test func testCodegenCompilesCoroutineCancellationEdgeCases() throws {
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            val timeoutResult = withTimeoutOrNull(1L) {
                delay(1000)
                1
            }
            println(timeoutResult)

            val cancelJob = launch {
                try {
                    delay(100)
                    println("unexpected-complete")
                } catch (e: CancellationException) {
                    println("cancelled")
                }
            }
            cancelJob.cancel()
            cancelJob.join()

            try {
                coroutineScope {
                    throw IllegalStateException("boom")
                }
            } catch (e: IllegalStateException) {
                println(e.message)
            }
        }
        """

        // `cancelJob.cancel()` runs synchronously right after `launch { }` returns, with no
        // intervening suspension point -- matching kotlinx.coroutines' CoroutineStart.DEFAULT
        // semantics, the child body never starts, so "cancelled" is never printed. Confirmed
        // against the real kotlinc/JVM reference via `Scripts/diff_cases/coroutine_cancellation_edge_cases.kt`.
        try assertKotlinOutput(
            source,
            moduleName: "CoroutineCancellationEdgeCases",
            expected:
                """
                null
                boom

                """
        )
    }

    // DEBT-CORO-005 / BUG-041: `job.cancel()` runs synchronously right after
    // `launch { }` returns, with no intervening suspension point. Under
    // CoroutineStart.DEFAULT the child body never starts, so its `finally`
    // block must not run -- only "done" is printed. A launch/cancel scheduling
    // race that let the child start would additionally print "finally".
    // Confirmed against the real kotlinc/JVM reference via
    // `Scripts/diff_cases/coroutine_launch_cancel_before_start_finally.kt`.
    @Test func testCodegenLaunchCancelBeforeStartSkipsFinally() throws {
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            val job = launch {
                try {
                    delay(Long.MAX_VALUE)
                } finally {
                    println("finally")
                }
            }
            job.cancel()
            job.join()
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "LaunchCancelBeforeStartSkipsFinally",
            expected:
                """
                done

                """
        )
    }
}
#endif
