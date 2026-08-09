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
struct CodegenBackendCharPredicatesTests {

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
    func testCodegenCharPredicateHelpersMatchExpectedOutput() throws {
        let source = """
        fun main() {
            println('A'.isLetter())
            println('1'.isDigit())
            println(' '.isWhitespace())
            println('7'.isLetterOrDigit())
        }
        """

        try assertKotlinOutput(source, moduleName: "CharPredicatesRuntime", expected: "true\ntrue\ntrue\ntrue\n")
    }

    // STDLIB-TEXT-PROP-008: Char.isIdentifierIgnorable end-to-end execution test
    @Test
    func testCodegenCharIsIdentifierIgnorableMatchesExpectedOutput() throws {
        let source = """
        fun main() {
            println('\\u00AD'.isIdentifierIgnorable())
            println('A'.isIdentifierIgnorable())
        }
        """

        try assertKotlinOutput(source, moduleName: "CharIsIdentifierIgnorableRuntime", expected: "true\nfalse\n")
    }

    @Test
    func testCodegenCharIsSurrogateMatchesExpectedOutput() throws {
        let source = """
        fun main() {
            println('\\uD800'.isSurrogate())
            println('\\uDFFF'.isSurrogate())
            println('A'.isSurrogate())
        }
        """
        try assertKotlinOutput(source, moduleName: "CharIsSurrogateRuntime", expected: "true\ntrue\nfalse\n")
    }

    // STDLIB-TEXT-PROP-016: Char.isTitleCase end-to-end execution test
    @Test
    func testCodegenCharIsTitleCaseMatchesExpectedOutput() throws {
        let source = """
        fun main() {
            println('\\u01C5'.isTitleCase())
            println('A'.isTitleCase())
        }
        """

        try assertKotlinOutput(source, moduleName: "CharIsTitleCaseRuntime", expected: "true\nfalse\n")
    }

    @Test
    func testCodegenCharCaseConversionHelpersHandleUnicodeMappings() throws {
        let source = """
        fun main() {
            println('ß'.uppercase())
            println('ǆ'.titlecase())
            println('İ'.lowercase())
        }
        """

        try assertKotlinOutput(source, moduleName: "CharCaseConversionRuntime", expected: "SS\nǅ\ni̇\n")
    }
}
#endif
