#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func isLinux() -> Bool {
#if os(Linux)
    return true
#else
    return false
#endif
}

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
struct CodegenBackendRegexOptionEdgeCasesTests {

    @Test(
        .disabled(if: isLinux(), "Regex option edge cases test temporarily disabled on Linux")
    )
    func testCodegenCompilesRegexOptionEdgeCases() throws {
        let source = """
        fun main() {
            val ignoreCase = Regex("hello", RegexOption.IGNORE_CASE)
            println(ignoreCase.containsMatchIn("HeLLo"))

            val dotDefault = Regex("a.b")
            val dotAll = Regex("a.b", RegexOption.DOT_MATCHES_ALL)
            println(dotDefault.containsMatchIn("a\\nb"))
            println(dotAll.containsMatchIn("a\\nb"))

            val combined = Regex(
                "^hello.world$",
                setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL, RegexOption.MULTILINE)
            )
            println(combined.containsMatchIn("HELLO\\nWORLD"))
            println(combined.matchEntire("hello\\nworld")?.value)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RegexOptionEdgeCases",
            expected:
                """
                true
                false
                true
                true
                hello
                world
                """ + "\n"
        )
    }
}
#endif
