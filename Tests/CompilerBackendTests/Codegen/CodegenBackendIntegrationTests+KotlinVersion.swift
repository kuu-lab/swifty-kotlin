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
struct CodegenBackendKotlinVersionTests {

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
    func testCodegenCompilesKotlinVersionComponents() throws {
        let source = """
        fun main() {
            val short = KotlinVersion(2, 1)
            val full = KotlinVersion(2, 1, 20)
            println(short.patch)
            println(full.major)
            println(full.minor)
            println(full.patch)
        }
        """

        try assertKotlinOutput(source, moduleName: "KotlinVersionComponents", expected: "0\n2\n1\n20\n")
    }

    @Test
    func testCodegenCompilesKotlinVersionComparisonHelpers() throws {
        let source = """
        fun main() {
            val baseline = KotlinVersion(2, 1, 20)
            println(KotlinVersion.CURRENT.isAtLeast(1, 0))
            println(baseline.compareTo(KotlinVersion(2, 1)) > 0)
            println(baseline < KotlinVersion(2, 2, 0))
            println(baseline.isAtLeast(2, 1, 21))
        }
        """

        try assertKotlinOutput(source, moduleName: "KotlinVersionComparisonHelpers", expected: "true\ntrue\ntrue\nfalse\n")
    }
}
#endif
