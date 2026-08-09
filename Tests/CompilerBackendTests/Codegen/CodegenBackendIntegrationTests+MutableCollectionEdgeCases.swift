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
struct CodegenBackendMutableCollectionEdgeCasesTests {

    @Test
    func testCodegenCompilesMutableCollectionEdgeCases() throws {
        let source = """
        fun main() {
            val zipped = listOf(1, 2, 3).zip(listOf("a", "b"))
            println(zipped)
            println(zipped.unzip().first)
            println(zipped.unzip().second)

            val map = mutableMapOf("a" to 1)
            map.putAll(mutableMapOf("b" to 2, "c" to 3))
            println(map.keys.toList())
            println(map.values.toList())

            val numbers = mutableListOf(1, 2, 3, 4, 5)
            numbers.removeAll(listOf(2, 5))
            println(numbers)

            numbers.retainAll(listOf(1, 4))
            println(numbers)

            val subtractable = mutableListOf(1, 2, 2, 3)
            subtractable -= 2
            subtractable -= listOf(3)
            println(subtractable)

            val mutableSet = mutableSetOf(1, 2, 3)
            mutableSet -= 2
            mutableSet -= listOf(3)
            println(mutableSet)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MutableCollectionEdgeCases",
            expected:
                """
                [(1, a), (2, b)]
                [1, 2]
                [a, b]
                [a, b, c]
                [1, 2, 3]
                [1, 3, 4]
                [1, 4]
                [1, 2]
                [1]
                """ + "\n"
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
