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
struct CodegenBackendFileAppendBytesTests {

    // STDLIB-IO-FN-001: File.appendBytes(array: ByteArray)
    @Test
    func testCodegenCompilesFileAppendBytes() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_append_bytes_codegen_test.bin"
            val file = File(path)
            file.delete()

            file.appendBytes(byteArrayOf(1, 2, 3))
            val bytes1 = file.readBytes()
            println(bytes1.size)
            for (b in bytes1) println(b)

            file.appendBytes(byteArrayOf(4, 5))
            val bytes2 = file.readBytes()
            println(bytes2.size)
            for (b in bytes2) println(b)

            file.delete()
            file.appendBytes(byteArrayOf(-128, -1))
            val bytes3 = file.readBytes()
            println(bytes3.size)
            for (b in bytes3) println(b)

            file.delete()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FileAppendBytes",
            expected:
                """
                3
                1
                2
                3
                5
                1
                2
                3
                4
                5
                2
                -128
                -1
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
