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

private func normalizeThrowableStderr(_ stderr: String) -> String {
    stderr
        .replacingOccurrences(of: "\r\n", with: "\n")
        .components(separatedBy: "\n")
        .filter { line in
            !(line.hasPrefix("warning: direct reference to protected function ")
                && line.contains(" may break pointer equality"))
        }
        .joined(separator: "\n")
}

@Suite
struct CodegenBackendThrowablePrintStackTraceTests {

    @Test
    func testCodegenThrowablePrintStackTraceWritesToStandardError() throws {
        let source = """
        class CustomRuntimeException : RuntimeException()

        fun main() {
            RuntimeException("stack message").printStackTrace()
            IndexOutOfBoundsException("index message").printStackTrace()
            CustomRuntimeException().printStackTrace()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ThrowablePrintStackTraceRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStderr = normalizeThrowableStderr(result.stderr)
            #expect(result.stdout == "")
            #expect(normalizedStderr == "RuntimeException: stack message\nIndexOutOfBoundsException: index message\nCustomRuntimeException\n")
        }
    }
}
#endif
