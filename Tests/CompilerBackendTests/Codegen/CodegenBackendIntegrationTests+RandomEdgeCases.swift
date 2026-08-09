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
struct CodegenBackendRandomEdgeCasesTests {

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
    func testCodegenRandomAsKotlinRandom() throws {
        let source = """
        import java.util.Random as JavaRandom
        import kotlin.random.Random
        import kotlin.random.asKotlinRandom

        fun main() {
            val r1: Random = JavaRandom(42).asKotlinRandom()
            val r2: Random = JavaRandom(42).asKotlinRandom()

            println(r1.nextInt(100) == r2.nextInt(100))
        }
        """

        try assertKotlinOutput(source, moduleName: "RandomAsKotlinRandom", expected: "true\n")
    }

    @Test
    func testCodegenRandomAsJavaRandom() throws {
        let source = """
        import kotlin.random.Random
        import kotlin.random.asJavaRandom

        fun main() {
            val javaRandom: java.util.Random = Random(42).asJavaRandom()
            println("ok")
        }
        """

        try assertKotlinOutput(source, moduleName: "RandomAsJavaRandom", expected: "ok\n")
    }

    @Test
    func testCodegenCompilesRandomEdgeCases() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val r1 = Random(1234)
            val r2 = Random(1234)

            println(r1.nextInt(100) == r2.nextInt(100))
            println(r1.nextInt(10, 20) == r2.nextInt(10, 20))
            println(r1.nextBoolean() == r2.nextBoolean())

            val ranged = Random(7)
            val nextInt = ranged.nextInt(5, 10)
            val nextDouble = ranged.nextDouble(1.0, 2.0)
            println(nextInt >= 5 && nextInt < 10)
            println(nextDouble >= 1.0 && nextDouble < 2.0)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RandomEdgeCases",
            expected:
                """
                true
                true
                true
                true
                true
                """
                + "\n"
        )
    }
}
#endif
