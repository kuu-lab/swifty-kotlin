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

// STDLIB-030: kotlin.io common - File read/write codegen tests
@Suite
struct CodegenBackendFileIOReadWriteTests {
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

    @Test func testCodegenFileWriteTextAndReadText() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_file_rw_codegen.txt"
            val file = File(path)
            file.delete()

            file.writeText("hello world")
            val text = file.readText()
            println(text)

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "FileWriteReadText", expected: "hello world\n")
    }

    @Test func testCodegenFileAppendText() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_file_append_text_codegen.txt"
            val file = File(path)
            file.delete()

            file.writeText("line1\n")
            file.appendText("line2\n")
            val text = file.readText()
            print(text)

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "FileAppendText", expected: "line1\nline2\n")
    }

    @Test func testCodegenFileReadLines() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_file_read_lines_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("alpha\nbeta\ngamma")

            val lines = file.readLines()
            println(lines.size)
            for (line in lines) {
                println(line)
            }

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "FileReadLines", expected: "3\nalpha\nbeta\ngamma\n")
    }
}
#endif
