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
struct CodegenBackendSequenceZipWithNextTests {

    @Test
    func testCodegenSequenceZipWithNextUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("sequence_zipwithnext.kt")

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceZipWithNextRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            do {
                try LinkPhase().run(ctx)
            } catch {
                let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
                Issue.record("LinkPhase failed: \(error)\n\(diagnostics.joined(separator: "\n"))")
                throw error
            }
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }
            #expect(
                !ctx.diagnostics.diagnostics.contains { $0.severity == .error },
                Comment(rawValue: diagnostics.joined(separator: "\n"))
            )

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(
                normalizedStdout ==
                "[(1, 2), (2, 3), (3, 4)]\n"
                    + "[(1, 2)]\n"
                    + "[2, 3, 4]\n"
                    + "[2]\n"
                    + "[]\n"
            )
        }
    }
}
#endif
