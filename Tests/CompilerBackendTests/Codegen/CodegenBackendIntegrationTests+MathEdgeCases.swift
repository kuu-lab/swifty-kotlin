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
struct CodegenBackendMathEdgeCasesTests {

    @Test
    func testCodegenCompilesMathEdgeCases() throws {
        let source = """
        import kotlin.math.*

        fun main() {
            println(sqrt(16.0))
            println(sqrt(-1.0).isNaN())

            println(abs(-42))
            println(abs(Double.NEGATIVE_INFINITY).isInfinite())

            println(round(2.4))
            println(round(-2.4))

            println(ceil(2.1))
            println(floor(-2.1))

            println(ceil(Double.NaN).isNaN())
            println(floor(Double.POSITIVE_INFINITY).isInfinite())

            // DEBT-DIFF-006 regression: keep List<Double> iteration in the
            // same test method so SwiftPM does not grow the generated
            // XCTest discovery expression with another entry.
            val values = listOf(3.2, 3.7, -2.3)
            for (value in values) {
                println(round(value))
                println(value.roundToInt())
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MathEdgeCases",
            expected:
                """
                4.0
                true
                42
                true
                2.0
                -2.0
                3.0
                -3.0
                true
                true
                3.0
                3
                4.0
                4
                -2.0
                -2
                """
                + "\n"
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
