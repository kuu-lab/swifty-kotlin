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
struct CodegenBackendSynchronizedTests {

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
    func testCodegenCompilesSynchronizedBlocks() throws {
        let source = """
        fun main() {
            val lock = object {}
            var counter = 0
            val result = synchronized(lock) {
                counter += 1
                val nested = synchronized(lock) { counter + 40 }
                nested + 1
            }
            println(result)
            println(counter)
        }
        """

        try assertKotlinOutput(source, moduleName: "SynchronizedBlocks", expected: "42\n1\n")
    }

    @Test
    func testCodegenPropagatesThrowFromSynchronizedBlock() throws {
        let source = """
        fun fail(): Int {
            throw IllegalStateException("boom")
        }

        fun main() {
            val lock = object {}
            try {
                synchronized(lock) { fail() }
                println("unreachable")
            } catch (e: Throwable) {
                println(e.message ?: "missing")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "SynchronizedThrow", expected: "boom\n")
    }

    @Test
    func testCodegenMutexDoubleUnlockPanicIncludesHelpfulMessage() throws {
        let source = """
        import kotlinx.coroutines.*
        import kotlinx.coroutines.sync.*

        fun main() = runBlocking {
            val mutex = Mutex()
            mutex.unlock()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MutexDoubleUnlock",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            do {
                _ = try CommandRunner.run(executable: outputBase, arguments: [])
                Issue.record("Expected Mutex.unlock() to trap on double unlock")
            } catch let CommandRunnerError.nonZeroExit(failed) {
                #expect(failed.exitCode != 0)
                #expect(failed.stderr.contains("KSwiftK panic"))
                #expect(
                    failed.stderr.contains("Mutex.unlock() called on an unlocked mutex"),
                    "Expected panic message to mention the unlocked mutex, got: \(failed.stderr)"
                )
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }
}
#endif
