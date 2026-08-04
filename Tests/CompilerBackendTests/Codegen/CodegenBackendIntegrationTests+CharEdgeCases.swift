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
struct CodegenBackendCharEdgeCasesTests {

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
    func testCodegenCompilesCharEdgeCases() throws {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

        fun main() {
            println('5'.digitToInt())
            println('9'.digitToInt())
            println('a'.digitToIntOrNull())
            println('a'.digitToIntOrNull(16))

            try {
                println('z'.digitToInt())
            } catch (e: Throwable) {
                println("invalid-char")
            }

            println(5.digitToChar())
            println(10.digitToChar(16))
            try {
                println(10.digitToChar())
            } catch (e: Throwable) {
                println("invalid-digit-to-char")
            }

            println('ß'.uppercase())
            println('ß'.uppercaseChar())
            println('İ'.lowercase())
            println('İ'.lowercaseChar())
            println('ǆ'.titlecaseChar())
            println('ß'.titlecaseChar())
            println('A'.isDefined())
            println(Char.isSupplementaryCodePoint(0x10000))
            println(Char.isSurrogatePair('\\uD800', '\\uDC00'))
            val bmp = Char.toChars(65)
            println(bmp.size)
            println(bmp[0])
            val pair = Char.toChars(0x10000)
            println(pair.size)
            println(Char.toCodePoint(pair[0], pair[1]))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharEdgeCases",
            expected:
                """
                5
                9
                null
                10
                invalid-char
                5
                A
                invalid-digit-to-char
                SS
                ß
                i\u{0307}
                i
                ǅ
                ß
                true
                true
                true
                1
                A
                2
                65536
                """
                + "\n"
        )
    }
}
#endif
