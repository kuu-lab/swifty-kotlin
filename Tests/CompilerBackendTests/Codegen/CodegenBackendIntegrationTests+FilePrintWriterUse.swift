@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
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

// STDLIB-030: kotlin.io common - PrintWriter codegen tests
@Suite(.serialized)
struct CodegenBackendFilePrintWriterUseTests {
    @Test
    func testCodegenFilePrintWriterUse() throws {
        let source = """
        import java.io.File
        import java.io.PrintWriter

        fun main() {
            val path = "/tmp/kswiftk_pw_use_codegen.txt"
            val file = File(path)
            file.delete()

            file.printWriter().use { pw ->
                pw.print("hello")
                pw.println(" world")
                pw.println()
                pw.println("done")
            }

            val lines = file.readLines()
            println(lines.size)
            for (l in lines) println(l)

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "FilePrintWriterUse", expected: "3\nhello world\n\ndone\n")
    }

    @Test
    func testCodegenFilePrintWriterExplicitFlushClose() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_pw_flush_codegen.txt"
            val file = File(path)
            file.delete()

            val pw = file.printWriter()
            pw.println("explicit flush and close")
            pw.flush()
            pw.close()

            println(file.readText())

            file.delete()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FilePrintWriterExplicitFlushClose",
            expected: "explicit flush and close\n\n"
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
