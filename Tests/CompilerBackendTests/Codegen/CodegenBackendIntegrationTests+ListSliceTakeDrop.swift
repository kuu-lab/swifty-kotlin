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
struct CodegenBackendListSliceTakeDropTests {

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

    // Regression for KSP-427: List take/drop/slice family must resolve to
    // bundled Kotlin source functions, not to stale runtime bridges or
    // unresolved external symbols.
    @Test
    func testCodegenListSliceTakeDropFamily() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3, 4, 5)
            println(list.take(3))
            println(list.drop(2))
            println(list.takeLast(2))
            println(list.dropLast(2))
            println(list.takeWhile { it < 3 })
            println(list.dropWhile { it < 3 })
            println(list.takeLastWhile { it > 3 })
            println(list.dropLastWhile { it > 3 })
            println(list.slice(1..3))
            println(list.slice(listOf(0, 2, 4)))
            println(list.subList(1, 4))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListSliceTakeDropRegression",
            expected: """
            [1, 2, 3]
            [3, 4, 5]
            [4, 5]
            [1, 2, 3]
            [1, 2]
            [3, 4, 5]
            [4, 5]
            [1, 2, 3]
            [2, 3, 4]
            [1, 3, 5]
            [2, 3, 4]

            """
        )
    }
}
#endif
