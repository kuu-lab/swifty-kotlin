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
struct CodegenBackendStringIsCharSequenceTests {

    @Test
    func testCodegenRuntimeBuiltStringIsCharSequence() throws {
        let source = """
        fun main() {
            val concatenated = "he" + "llo"
            println(concatenated is CharSequence)
            println(StringBuilder("x").toString() is CharSequence)
            println(buildString { append("y") } is CharSequence)
            val erased: Any = concatenated
            println(erased is CharSequence)
            println(concatenated is Comparable<*>)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RuntimeBuiltStringIsCharSequence",
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

    @Test
    func testCodegenRuntimeBuiltStringIsNotUnrelatedNominalType() throws {
        let source = """
        interface Marker

        class Impl : Marker

        fun main() {
            val concatenated = "he" + "llo"
            println(concatenated is Marker)
            println(concatenated is List<*>)
            println(Impl() is CharSequence)
            println(1 is CharSequence)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RuntimeBuiltStringIsNotUnrelatedNominalType",
            expected:
                """
                false
                false
                false
                false
                """
                + "\n"
        )
    }

    @Test
    func testCodegenRuntimeBuiltStringCastToCharSequence() throws {
        let source = """
        fun main() {
            val concatenated = "he" + "llo"
            println((concatenated as CharSequence) === concatenated)
            println((concatenated as? CharSequence) != null)
            println((42 as? CharSequence) == null)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "RuntimeBuiltStringCastToCharSequence",
            expected:
                """
                true
                true
                true
                """
                + "\n"
        )
    }
}
#endif
