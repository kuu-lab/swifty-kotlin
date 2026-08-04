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
struct CodegenBackendCollectionFlatMapTests {
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

    @Test func testCodegenListFlatMapBasic() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            val result = values.flatMap { listOf(it, it * 10) }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionFlatMapBasic", expected: "[1, 10, 2, 20, 3, 30]\n")
    }

    @Test func testCodegenListFlatMapWithEmptyInput() throws {
        let source = """
        fun main() {
            val values = emptyList<Int>()
            val result = values.flatMap { listOf(it, it * 10) }
            println(result)
            println(result.size)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionFlatMapEmptyInput", expected: "[]\n0\n")
    }

    @Test func testCodegenListFlatMapWithConditionalEmptySubList() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3, 4, 5)
            val result = values.flatMap { if (it % 2 == 0) listOf(it) else listOf<Int>() }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionFlatMapConditionalEmpty", expected: "[2, 4]\n")
    }

    @Test func testCodegenListFlatMapIndexed() throws {
        let source = """
        fun main() {
            val values = listOf(10, 20, 30)
            val result = values.flatMapIndexed { index, value -> listOf(index, value) }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionFlatMapIndexed", expected: "[0, 10, 1, 20, 2, 30]\n")
    }
}
#endif
