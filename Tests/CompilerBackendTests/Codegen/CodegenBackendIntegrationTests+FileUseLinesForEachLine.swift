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

// STDLIB-030: kotlin.io common - useLines / forEachLine codegen tests
@Suite
struct CodegenBackendFileUseLinesForEachLineTests {

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
    func testCodegenFileUseLines() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_file_uselines_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("alpha\nbeta\ngamma")

            val count = file.useLines { lines ->
                lines.count()
            }
            println(count)

            file.useLines { lines ->
                lines.forEach { line -> println(line) }
            }

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "FileUseLines", expected: "3\nalpha\nbeta\ngamma\n")
    }

    @Test
    func testCodegenFileForEachLine() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_file_foreachline_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("one\ntwo\nthree")

            file.forEachLine { line ->
                println(line)
            }

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "FileForEachLine", expected: "one\ntwo\nthree\n")
    }

    @Test
    func testCodegenBufferedReaderUseLines() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_br_uselines_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("p\nq\nr")

            file.bufferedReader().useLines { lines ->
                lines.forEach { l -> println(l) }
            }

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "BufferedReaderUseLines", expected: "p\nq\nr\n")
    }

    @Test
    func testCodegenBufferedReaderForEachLine() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_br_foreachline_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("row1\nrow2\nrow3")

            val reader = file.bufferedReader()
            reader.forEachLine { line ->
                println(line)
            }

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "BufferedReaderForEachLine", expected: "row1\nrow2\nrow3\n")
    }

    @Test
    func testCodegenFileUseLinesEmptyFile() throws {
        let source = """
        import java.io.File

        fun main() {
            val path = "/tmp/kswiftk_file_uselines_empty_codegen.txt"
            val file = File(path)
            file.delete()
            file.writeText("")

            val count = file.useLines { lines ->
                lines.count()
            }
            println(count)

            file.delete()
        }
        """

        try assertKotlinOutput(source, moduleName: "FileUseLinesEmpty", expected: "0\n")
    }
}
#endif
