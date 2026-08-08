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
struct CodegenBackendSystemGetTimeNanosTests {

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
    func testGetTimeNanosReturnsPositiveLong() throws {
        let source = """
        import kotlin.system.getTimeNanos

        fun main() {
            val t = getTimeNanos()
            println(t > 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "GetTimeNanosPositive", expected: "true\n")
    }

    @Test
    func testGetTimeNanosSuccessiveCallsNonDecreasing() throws {
        let source = """
        import kotlin.system.getTimeNanos

        fun main() {
            val t1 = getTimeNanos()
            val t2 = getTimeNanos()
            println(t2 >= t1)
        }
        """

        try assertKotlinOutput(source, moduleName: "GetTimeNanosNonDecreasing", expected: "true\n")
    }

    @Test
    func testGetTimeNanosCanMeasureElapsedTime() throws {
        let source = """
        import kotlin.system.getTimeNanos

        fun main() {
            val before = getTimeNanos()
            var sum = 0L
            for (i in 1..1000) sum += i
            val after = getTimeNanos()
            println(after >= before)
            println(sum == 500500L)
        }
        """

        try assertKotlinOutput(source, moduleName: "GetTimeNanosElapsed", expected: "true\ntrue\n")
    }
}
#endif
