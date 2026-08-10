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

@Suite
struct CodegenBackendNegativeZeroMemberCallsTests {

    @Test
    func testNegativeZeroDoubleToString() throws {
        let source = """
        fun main() {
            println((-0.0).toString())
            val z: Double = -0.0
            println(z.toString())
        }
        """
        try assertKotlinOutput(source, moduleName: "NegZeroDoubleToString", expected: "-0.0\n-0.0\n")
    }

    @Test
    func testNegativeZeroFloatToString() throws {
        let source = """
        fun main() {
            println((-0.0f).toString())
            val z: Float = -0.0f
            println(z.toString())
        }
        """
        try assertKotlinOutput(source, moduleName: "NegZeroFloatToString", expected: "-0.0\n-0.0\n")
    }

    @Test
    func testNegativeZeroReturnValue() throws {
        let source = """
        fun negZeroDouble(): Double = -0.0
        fun negZeroFloat(): Float = -0.0f
        fun main() {
            println(negZeroDouble())
            println(negZeroFloat())
        }
        """
        try assertKotlinOutput(source, moduleName: "NegZeroReturnValue", expected: "-0.0\n-0.0\n")
    }
}
#endif
