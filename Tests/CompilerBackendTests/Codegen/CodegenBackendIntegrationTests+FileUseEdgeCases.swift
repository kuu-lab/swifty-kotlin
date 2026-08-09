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
struct CodegenBackendFileUseEdgeCasesTests {

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
    func testCodegenCompilesFileUseEdgeCases() throws {
        let source = """
        import java.io.Closeable
        import java.io.File

        class TraceResource(private val name: String) : Closeable {
            override fun close() {
                println("close:$name")
            }
        }

        fun main() {
            val result = TraceResource("ok").use {
                println("use:ok")
                "done"
            }
            println(result)

            try {
                TraceResource("fail").use {
                    println("use:fail")
                    error("boom")
                }
            } catch (e: Throwable) {
                println("caught")
            }

            val nullable: TraceResource? = null
            println(nullable?.use { "nope" })

            val file = File("/tmp/kswiftk_file_use_edge_cases.txt")
            file.delete()
            println(file.exists())
            println(file.createNewFile())
            println(file.exists())
            println(file.delete())
            println(file.exists())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FileUseEdgeCases",
            expected:
                """
                use:ok
                close:ok
                done
                use:fail
                close:fail
                caught
                null
                false
                true
                true
                true
                false
                """
                + "\n"
        )
    }
}
#endif
