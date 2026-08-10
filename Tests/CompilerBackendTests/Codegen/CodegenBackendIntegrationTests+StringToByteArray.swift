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
struct CodegenBackendStringToByteArrayTests {

    @Test
    func testCodegenStringToByteArrayNoArg() throws {
        let source = """
        fun main() {
            val bytes = "abc".toByteArray()
            println(bytes.size)
            println(bytes[0])
            println(bytes[1])
            println(bytes[2])
        }
        """
        try assertKotlinOutput(source, moduleName: "StringToByteArrayNoArg", expected: "3\n97\n98\n99\n")
    }

    @Test
    func testCodegenStringToByteArrayCharsets() throws {
        let source = """
        fun main() {
            val utf8 = "hello".toByteArray(Charsets.UTF_8)
            println(utf8.size)

            val latin1 = "hello".toByteArray(Charsets.ISO_8859_1)
            println(latin1.size)

            val ascii = "hello".toByteArray(Charsets.US_ASCII)
            println(ascii.size)

            // UTF-16BE: 2 bytes per BMP char, no BOM
            val utf16be = "ab".toByteArray(Charsets.UTF_16BE)
            println(utf16be.size)

            // UTF-16LE: 2 bytes per BMP char, no BOM
            val utf16le = "ab".toByteArray(Charsets.UTF_16LE)
            println(utf16le.size)
        }
        """
        try assertKotlinOutput(source, moduleName: "StringToByteArrayCharsets", expected: "5\n5\n5\n4\n4\n")
    }
}
#endif
