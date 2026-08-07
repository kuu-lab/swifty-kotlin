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
struct CodegenBackendCinteropByteArrayToKStringTests {

    // STDLIB-CINTEROP-FN-029: ByteArray.toKString(startIndex, endIndex, throwOnInvalidSequence)
    @Test
    func testCodegenCinteropByteArrayToKString() throws {
        let source = """
        import kotlinx.cinterop.ExperimentalForeignApi
        import kotlinx.cinterop.toKString

        @OptIn(ExperimentalForeignApi::class)
        fun main() {
            val bytes = "hello".encodeToByteArray()
            println(bytes.toKString())
            println(bytes.toKString(1, 4))
            println(bytes.toKString(0, bytes.size, false))

            val malformed = byteArrayOf((-61).toByte(), 40.toByte())
            println(malformed.toKString().length > 0)
            try {
                println(malformed.toKString(0, 2, true))
            } catch (e: Throwable) {
                println("caught")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CinteropByteArrayToKString",
            expected:
                """
                hello
                ell
                hello
                true
                caught
                """
                + "\n"
        )
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
}
#endif
