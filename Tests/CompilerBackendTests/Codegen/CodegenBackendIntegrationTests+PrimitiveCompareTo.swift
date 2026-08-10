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
struct CodegenBackendPrimitiveCompareToTests {

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
    func testCodegenCompilesPrimitiveCompareTo() throws {
        let source = """
        fun main() {
            // Int — direct member call
            println(10.compareTo(20))
            println(20.compareTo(10))
            println(7.compareTo(7))
            // Int — inside a (Int, Int) -> Int lambda
            val cmpInt: (Int, Int) -> Int = { x, y -> x.compareTo(y) }
            println(cmpInt(30, 5))
            // Long
            println(100L.compareTo(200L))
            // Double — direct and inside a (Double, Double) -> Int lambda
            println(2.5.compareTo(1.5))
            val cmpDouble: (Double, Double) -> Int = { x, y -> x.compareTo(y) }
            println(cmpDouble(1.0, 9.0))
            // Float — direct and inside a (Float, Float) -> Int lambda
            println(2.5f.compareTo(1.5f))
            val cmpFloat: (Float, Float) -> Int = { x, y -> x.compareTo(y) }
            println(cmpFloat(1.0f, 9.0f))
            // Boolean (false < true)
            println(false.compareTo(true))
        }
        """
        try assertKotlinOutput(source, moduleName: "PrimitiveCompareTo", expected: "-1\n1\n0\n1\n-1\n1\n-1\n1\n-1\n-1\n")
    }
}
#endif
