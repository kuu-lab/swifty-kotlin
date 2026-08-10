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
struct CodegenBackendSystemGetTimeMillisTests {

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
    func testGetTimeMillisReturnsPositiveLong() throws {
        let source = """
        import kotlin.system.getTimeMillis

        fun main() {
            val t = getTimeMillis()
            println(t > 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "GetTimeMillisPositive", expected: "true\n")
    }

    @Test
    func testGetTimeMillisIsInReasonableEpochRange() throws {
        // 2017-01-01 00:00:00 UTC = 1_483_228_800_000 ms
        // 2049-01-01 00:00:00 UTC = 2_493_072_000_000 ms
        let source = """
        import kotlin.system.getTimeMillis

        fun main() {
            val t = getTimeMillis()
            println(t > 1_483_228_800_000L)
            println(t < 2_493_072_000_000L)
        }
        """

        try assertKotlinOutput(source, moduleName: "GetTimeMillisEpochRange", expected: "true\ntrue\n")
    }

    @Test
    func testGetTimeMillisSuccessiveCallsNonDecreasing() throws {
        let source = """
        import kotlin.system.getTimeMillis

        fun main() {
            val t1 = getTimeMillis()
            val t2 = getTimeMillis()
            println(t2 >= t1)
        }
        """

        try assertKotlinOutput(source, moduleName: "GetTimeMillisNonDecreasing", expected: "true\n")
    }

    @Test
    func testGetTimeMillisCanMeasureElapsedTime() throws {
        let source = """
        import kotlin.system.getTimeMillis

        fun main() {
            val before = getTimeMillis()
            var sum = 0L
            for (i in 1..1000) sum += i
            val after = getTimeMillis()
            println(after >= before)
            println(sum == 500500L)
        }
        """

        try assertKotlinOutput(source, moduleName: "GetTimeMillisElapsed", expected: "true\ntrue\n")
    }
}
#endif
