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
struct CodegenBackendComparisonsRuntimeEdgeCasesTests {

    @Test
    func testCodegenCompilesComparisonsRuntimeEdgeCases() throws {
        let source = """
        fun main() {
            val words = listOf("pear", "apple", "fig")
            val byLength = compareBy<String> { it.length }

            println(words.maxWithOrNull(byLength))
            println(words.minWithOrNull(byLength))

            val empty = emptyList<String>()
            println(empty.maxWithOrNull(byLength))
            println(empty.minWithOrNull(byLength))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparisonsRuntimeEdgeCases",
            expected:
                """
                apple
                fig
                null
                null
                """ + "\n"
        )
    }

    @Test
    func testCodegenCompilesCompareByDescendingSelector() throws {
        let source = """
        fun main() {
            val words = listOf("pear", "fig", "apple")
            val byLengthDesc = compareByDescending<String> { it.length }
            println(words.sortedWith(byLengthDesc))
        }
        """

        try assertKotlinOutput(source, moduleName: "CompareByDescendingSelector", expected: "[apple, pear, fig]\n")
    }

    @Test
    func testCodegenListMinWithReturnsComparatorMinimumAndThrowsOnEmpty() throws {
        let source = """
        fun main() {
            println(listOf(5, 2, 3).minWith(reverseOrder<Int>()))
            try {
                emptyList<Int>().minWith(reverseOrder<Int>())
                println("missing")
            } catch (e: NoSuchElementException) {
                println("empty")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMinWithRuntime", expected: "5\nempty\n")
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
