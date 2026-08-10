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
struct CodegenBackendNegativeArraySizeExceptionTests {

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
    func testCodegenByteArrayWithInitThrowsNegativeArraySizeExceptionForNegativeSize() throws {
        let source = """
        fun main() {
            try {
                val a = ByteArray(-1) { 0 }
                println("no throw, size=${a.size}")
            } catch (e: NegativeArraySizeException) {
                println("threw: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ByteArrayNegativeSize", expected: "threw: -1\n")
    }

    @Test
    func testCodegenByteArrayWithInitNegativeSizeIsCatchableAsGenericException() throws {
        let source = """
        fun main() {
            try {
                val a = ByteArray(-1) { 0 }
                println("no throw, size=${a.size}")
            } catch (e: Exception) {
                println("threw: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "ByteArrayNegativeSizeGenericCatch", expected: "threw: -1\n")
    }

    @Test
    func testCodegenSiblingSizedArrayConstructorsThrowNegativeArraySizeException() throws {
        let source = """
        fun main() {
            try {
                IntArray(-2) { it }
                println("no throw")
            } catch (e: NegativeArraySizeException) {
                println("int: ${e.message}")
            }

            try {
                Array(-3) { "x" }
                println("no throw")
            } catch (e: NegativeArraySizeException) {
                println("generic: ${e.message}")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SiblingArrayConstructorsNegativeSize",
            expected: "int: -2\ngeneric: -3\n"
        )
    }

    @Test
    func testCodegenByteArrayWithInitPositiveSizeStillWorks() throws {
        let source = """
        fun main() {
            val a = ByteArray(3) { it.toByte() }
            println(a.joinToString())
        }
        """

        try assertKotlinOutput(source, moduleName: "ByteArrayPositiveSizeRegression", expected: "0, 1, 2\n")
    }
}
#endif
