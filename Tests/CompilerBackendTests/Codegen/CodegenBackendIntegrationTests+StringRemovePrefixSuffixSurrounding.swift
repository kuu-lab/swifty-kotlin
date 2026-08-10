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
struct CodegenBackendStringRemovePrefixSuffixSurroundingTests {

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
    func testCodegenStringRemovePrefixSuffixSurrounding() throws {
        let source = """
        fun main() {
            // removePrefix
            println("HelloWorld".removePrefix("Hello"))
            println("HelloWorld".removePrefix("Goodbye"))
            println("prefix".removePrefix("prefix"))

            // removeSuffix
            println("HelloWorld".removeSuffix("World"))
            println("HelloWorld".removeSuffix("Earth"))
            println("suffix".removeSuffix("suffix"))

            // removeSurrounding(delimiter) — both ends must match the same delimiter
            println("***star***".removeSurrounding("***"))
            println("[bracketed]".removeSurrounding("["))
            println("ab".removeSurrounding("ab"))

            // removeSurrounding(prefix, suffix) — prefix and suffix can differ
            println("<div>content</div>".removeSurrounding("<div>", "</div>"))
            println("[item]".removeSurrounding("[", "]"))
            println("no-match".removeSurrounding("<", ">"))
        }
        """

        try assertKotlinOutput(source, moduleName: "StringRemovePrefixSuffixSurrounding", expected: "World\nHelloWorld\n\nHello\nHelloWorld\n\nstar\n[bracketed]\nab\ncontent\nitem\nno-match\n")
    }
}
#endif
