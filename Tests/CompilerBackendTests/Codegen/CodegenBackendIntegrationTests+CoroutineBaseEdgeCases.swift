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
struct CodegenBackendCoroutineBaseEdgeCasesTests {
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

    @Test(
        .disabled("user-defined suspend delay/exception paths not yet correct (STDLIB-CORO-001, DEBT-CORO-004)")
    )
    func testCodegenCompilesCoroutineBaseEdgeCases() throws {
        let source = """
        import kotlinx.coroutines.*

        suspend fun step(value: Int): Int {
            delay(1)
            return value + 1
        }

        suspend fun failStep(): Int {
            delay(1)
            throw IllegalStateException("suspend-boom")
        }

        fun main() = runBlocking {
            val ok = step(41)
            println(ok)

            try {
                failStep()
            } catch (e: IllegalStateException) {
                println(e.message)
            }

            val resumed = withContext(Dispatchers.Default) {
                step(9)
            }
            println(resumed)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CoroutineBaseEdgeCases",
            expected:
                """
                42
                suspend-boom
                10
                """
        )
    }
}
#endif
