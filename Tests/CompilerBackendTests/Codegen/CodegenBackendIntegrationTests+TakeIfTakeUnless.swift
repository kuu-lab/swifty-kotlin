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
struct CodegenBackendTakeIfTakeUnlessTests {

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
    func testCodegenCompilesTakeIfTakeUnless() throws {
        let source = """
        fun main() {
            // takeIf: returns receiver if predicate is true, else null
            println(10.takeIf { it > 5 })   // 10
            println(10.takeIf { it > 20 })  // null
            println(0.takeIf { it == 0 })   // 0

            // takeUnless: returns receiver if predicate is false, else null
            println(10.takeUnless { it > 5 })   // null
            println(10.takeUnless { it > 20 })  // 10
            println(0.takeUnless { it != 0 })  // 0
        }
        """

        try assertKotlinOutput(source, moduleName: "TakeIfTakeUnless", expected: "10\nnull\n0\nnull\n10\n0\n")
    }

    // STDLIB-TEXT-FN-079: String.takeIf / String.takeUnless
    @Test
    func testCodegenStringTakeIfTakeUnless() throws {
        let source = """
        fun main() {
            // takeIf: returns receiver String if predicate is true, else null
            println("hello".takeIf { it.isNotEmpty() })   // hello
            println("".takeIf { it.isNotEmpty() })        // null
            println("kotlin".takeIf { it.length > 3 })   // kotlin
            println("hi".takeIf { it.length > 5 })       // null

            // takeUnless: returns receiver String if predicate is false, else null
            println("hello".takeUnless { it.isEmpty() })  // hello
            println("".takeUnless { it.isEmpty() })       // null
            println("kotlin".takeUnless { it.length > 10 })  // kotlin
            println("hello world".takeUnless { it.length > 5 })  // null
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringTakeIfTakeUnless",
            expected: "hello\nnull\nkotlin\nnull\nhello\nnull\nkotlin\nnull\n"
        )
    }
}
#endif
