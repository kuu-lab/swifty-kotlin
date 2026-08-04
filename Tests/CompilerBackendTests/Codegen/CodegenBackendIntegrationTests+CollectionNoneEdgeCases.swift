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

@Suite
struct CodegenBackendCollectionNoneEdgeCasesTests {
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
    func codegenCollectionNoneEdgeCases() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.none())
            println(values.none { it > 3 })
            println(values.none { it == 2 })

            val emptyValues = emptyList<Int>()
            println(emptyValues.none())

            val array = arrayOf(1, 2, 3)
            println(array.none())
            println(array.none { it < 0 })

            val map = mapOf("a" to 1, "b" to 2)
            println(map.none { it.value > 2 })
            println(map.none { it.key == "a" })

            val set = setOf(1, 2, 3)
            println(set.none())
            println(set.none { it == 4 })
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionNoneEdgeCases", expected: "false\ntrue\nfalse\ntrue\nfalse\ntrue\ntrue\nfalse\nfalse\ntrue\n")
    }
}
#endif
