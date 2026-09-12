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
struct CodegenBackendStringWithIndexTests {

    @Test
    func testCodegenStringWithIndexUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("string_withindex.kt")

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringWithIndexRuntime",
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
            #expect(
                !ctx.diagnostics.diagnostics.contains { $0.severity == .error },
                Comment(rawValue: ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: "\n"))
            )

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(
                normalizedStdout
                    == "IndexedValue(index=0, value=h)\n"
                    + "IndexedValue(index=1, value=e)\n"
                    + "IndexedValue(index=2, value=l)\n"
                    + "IndexedValue(index=3, value=l)\n"
                    + "IndexedValue(index=4, value=o)\n"
                    + "done\n"
            )
        }
    }
}
#endif
