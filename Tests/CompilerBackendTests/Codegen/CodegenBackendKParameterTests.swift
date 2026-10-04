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
struct CodegenBackendKParameterTests {

    @Test
    func testKParameterPropertyAccessCompiles() throws {
        let source = """
        import kotlin.reflect.KParameter
        import kotlin.reflect.KType

        fun inspectIndex(p: KParameter): Int = p.index

        fun inspectName(p: KParameter): String? = p.name

        fun inspectType(p: KParameter): KType = p.type

        fun inspectOptional(p: KParameter): Boolean = p.isOptional

        fun inspectKind(p: KParameter): Int = p.kind

        fun main() {
            println("kparameter-codegen-ok")
        }
        """

        try assertTrimmedKotlinOutput(
            source,
            moduleName: "KParameterPropertyAccess",
            expected: "kparameter-codegen-ok"
        )
    }

    @Test
    func testKParameterPropertyAccessInConditional() throws {
        let source = """
        import kotlin.reflect.KParameter

        fun describeKind(p: KParameter): String {
            return when (p.kind) {
                0 -> "INSTANCE"
                1 -> "EXTENSION_RECEIVER"
                else -> "VALUE"
            }
        }

        fun main() {
            println("kparameter-conditional-codegen-ok")
        }
        """

        try assertTrimmedKotlinOutput(
            source,
            moduleName: "KParameterConditional",
            expected: "kparameter-conditional-codegen-ok"
        )
    }

    @Test
    func testKParameterNullableNameAndIsOptionalCompile() throws {
        let source = """
        import kotlin.reflect.KParameter

        fun label(p: KParameter): String {
            val n = p.name ?: "<no-name>"
            val opt = if (p.isOptional) "?" else ""
            return n + opt
        }

        fun main() {
            println("kparameter-nullable-codegen-ok")
        }
        """

        try assertTrimmedKotlinOutput(
            source,
            moduleName: "KParameterNullableName",
            expected: "kparameter-nullable-codegen-ok"
        )
    }

    private func assertTrimmedKotlinOutput(
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
            #expect(result.stdout.trimmingCharacters(in: .newlines) == expected)
        }
    }
}
#endif
