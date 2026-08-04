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
struct CodegenBackendInlineFunctionExceptionPropagationTests {

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
    func testCodegenReifiedInlineCastFailureCaughtByCallerTryCatch() throws {
        let source = """
        inline fun <reified T> reifiedCast(value: Any?): T {
            return value as T
        }

        fun main() {
            try {
                reifiedCast<String>(42)
            } catch (e: Exception) {
                println("caught: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ReifiedInlineCastCaughtRuntime", expected: "caught: ClassCastException\n")
    }

    @Test
    func testCodegenReifiedInlineCastSuccessDoesNotTriggerCatch() throws {
        let source = """
        inline fun <reified T> reifiedCast(value: Any?): T {
            return value as T
        }

        fun main() {
            try {
                println(reifiedCast<String>("hello"))
            } catch (e: Exception) {
                println("unexpected: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ReifiedInlineCastSuccessRuntime", expected: "hello\n")
    }

    @Test
    func testCodegenInlineLambdaCastFailureCaughtByCallerTryCatch() throws {
        let source = """
        inline fun <T> runIt(block: () -> T): T {
            return block()
        }

        fun main() {
            try {
                runIt<String> {
                    val x: Any? = 42
                    x as String
                }
            } catch (e: ClassCastException) {
                println("caught: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "InlineLambdaCastCaughtRuntime", expected: "caught: ClassCastException\n")
    }
}
#endif
