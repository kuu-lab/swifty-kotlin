#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
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
        package traces

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
            let lines = normalizedStderr.split(separator: "\n").map(String.init)
            let headers = lines.filter { !$0.hasPrefix("\tat ") }
            #expect(headers == [
                "java.lang.RuntimeException: stack message",
                "java.lang.IndexOutOfBoundsException: index message",
                "traces.CustomRuntimeException",
            ])
            for header in headers {
                let index = try #require(lines.firstIndex(of: header))
                #expect(index + 1 < lines.count)
                #expect(lines[index + 1].hasPrefix("\tat "))
            }
        }
    }

    @Test
    func testStackTraceToStringIncludesSavedFramesAndQualifiedHeaders() throws {
        let source = """
        package traces

        class CustomException : RuntimeException("custom")
        class RenderedException : RuntimeException() {
            override fun toString(): String = "rendered exception"
        }

        fun main() {
            val e = IllegalStateException("e")
            val trace = e.stackTraceToString()
            println(trace.startsWith("java.lang.IllegalStateException: e\\n\\tat "))
            println(trace == e.stackTraceToString())
            println(RuntimeException().stackTraceToString().startsWith("java.lang.RuntimeException\\n\\tat "))
            println(CustomException().stackTraceToString().startsWith("traces.CustomException: custom\\n\\tat "))
            println(RenderedException().stackTraceToString().startsWith("rendered exception\\n\\tat "))
            e.initCause(IllegalArgumentException("cause"))
            e.addSuppressed(RuntimeException("suppressed"))
            val chained = e.stackTraceToString()
            println(chained.contains("Suppressed: java.lang.RuntimeException: suppressed\\n\\tat "))
            println(chained.contains("Caused by: java.lang.IllegalArgumentException: cause\\n\\tat "))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ThrowableStackTraceToString",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout == String(repeating: "true\n", count: 7))
            #expect(normalizeThrowableStderr(result.stderr).isEmpty)
        }
    }
}
#endif
