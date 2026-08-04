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

// STDLIB-COMP-FN-044: minOf(Long, Long) — 2-arg Long overload end-to-end codegen tests.
@Suite
struct CodegenBackendMinOfLongEdgeCasesTests {

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
    func testCodegenCompilesMinOfLongEdgeCases() throws {
        let source = """
        fun main() {
            println(minOf(3L, 7L))
            println(minOf(-10L, -3L))
            println(minOf(0L, 0L))
            println(minOf(Long.MIN_VALUE, Long.MAX_VALUE))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MinOfLongEdgeCases",
            expected: """
            3
            -10
            0
            -9223372036854775808

            """
        )
    }

    @Test
    func testCodegenMinOfLongReturnsCorrectType() throws {
        let source = """
        fun minLong(a: Long, b: Long): Long = minOf(a, b)

        fun main() {
            val result: Long = minLong(100L, 200L)
            println(result)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MinOfLongReturnType",
            expected: "100\n"
        )
    }
}
#endif
