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
struct CodegenBackendRegexEdgeCasesTests {

    @Test
    func testCodegenCompilesRegexEdgeCases() throws {
        let source = """
        fun main() {
            val regex = Regex("[a-z]+")
            println(regex.containsMatchIn("123abc"))
            println(regex.matchEntire("abc")?.value)
            println(regex.matchEntire("abc123"))

            println("a b   c".replace(Regex("\\\\s+"), "-"))
            println("one1two2three".split(Regex("[0-9]+")))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RegexEdgeCases",
            expected:
                """
                true
                abc
                null
                a-b-c
                [one, two, three]
                """
                + "\n"
        )
    }
}
#endif
