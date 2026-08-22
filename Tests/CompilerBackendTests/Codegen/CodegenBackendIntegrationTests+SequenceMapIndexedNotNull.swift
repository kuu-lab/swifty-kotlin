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
    irFlags: [String] = [],
    includeStdlib: Bool = true
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        irFlags: irFlags,
        includeStdlib: includeStdlib,
        stdlibLibraryPath: try testStdlibArtifactPath()
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
struct CodegenBackendSequenceMapIndexedNotNullTests {

    @Test
    func testCodegenSequenceMapIndexedNotNullReturnsLazyFilteredMappedSequence() throws {
        let source = """
        var counter = 0

        fun main() {
            val mapped = sequenceOf(10, 20, 30, 40)
                .mapIndexedNotNull { index, value ->
                    counter++
                    if (index % 2 == 0) index + value else null
                }

            println(mapped.take(1).toList())
            println(counter)
            println(mapped.toList())
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceMapIndexedNotNullRuntime", expected: "[10]\n1\n[10, 32]\n")
    }

    @Test
    func testCodegenSequenceMapIndexedNotNullUsesBundledSourceImplementation() throws {
        let source = """
        fun render(): Sequence<Int> {
            return sequenceOf(10, 20, 30).mapIndexedNotNull { index, value ->
                if (index % 2 == 0) index + value else null
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "SequenceMapIndexedNotNullKIR",
                emit: .kirDump,
                outputPath: outputBase
            )

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            // Artifact imports may inline the source-backed transform; a
            // direct consumer callee is therefore not a stable assertion.
            // The imported sequence factory and retired-bridge absence remain
            // concrete artifact-backed routing checks.
            #expect(containsKotlinCallee("sequenceOf", in: callees))
            #expect(!callees.contains("kk_sequence_mapIndexedNotNull"), "Sequence.mapIndexedNotNull should no longer route through the retired native bridge, got: \(callees)")
        }
    }
}
#endif
