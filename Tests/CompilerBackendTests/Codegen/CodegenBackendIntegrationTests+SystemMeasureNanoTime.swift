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
struct CodegenBackendSystemMeasureNanoTimeTests {

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
    func testMeasureNanoTimeReturnsNonNegativeLong() throws {
        let source = """
        import kotlin.system.measureNanoTime

        fun main() {
            val elapsed = measureNanoTime {
                var sum = 0L
                for (i in 1..100) sum += i
            }
            println(elapsed >= 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureNanoTimeNonNegative", expected: "true\n")
    }

    @Test
    func testMeasureNanoTimeBlockBodyExecutes() throws {
        let source = """
        import kotlin.system.measureNanoTime

        fun main() {
            var executed = false
            val elapsed = measureNanoTime {
                executed = true
            }
            println(executed)
            println(elapsed >= 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureNanoTimeBlockExecutes", expected: "true\ntrue\n")
    }

    @Test
    func testMeasureNanoTimeSideEffectsAreVisible() throws {
        let source = """
        import kotlin.system.measureNanoTime

        fun main() {
            var counter = 0
            measureNanoTime {
                counter += 1
                counter += 1
                counter += 1
            }
            println(counter)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureNanoTimeSideEffects", expected: "3\n")
    }

    @Test
    func testMeasureNanoTimeNestedCalls() throws {
        let source = """
        import kotlin.system.measureNanoTime

        fun main() {
            val outer = measureNanoTime {
                val inner = measureNanoTime {
                    var x = 0
                    for (i in 1..10) x += i
                }
                println(inner >= 0)
            }
            println(outer >= 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureNanoTimeNested", expected: "true\ntrue\n")
    }
}
#endif
