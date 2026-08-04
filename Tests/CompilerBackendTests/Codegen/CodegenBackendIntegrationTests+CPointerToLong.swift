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
struct CodegenBackendCPointerToLongTests {

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
    func testCPointerToLongNullReturnsZero() throws {
        let source = """
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toLong

        fun main() {
            val nullPtr: CPointer<ByteVar>? = null
            println(nullPtr.toLong())
        }
        """

        try assertKotlinOutput(source, moduleName: "CPointerToLongNull", expected: "0\n")
    }

    @Test
    func testCPointerToLongFunctionWrapperCompilesAndLinks() throws {
        let source = """
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toLong

        fun pointerAddress(p: CPointer<ByteVar>?): Long = p.toLong()

        fun main() {
            println(pointerAddress(null))
        }
        """

        try assertKotlinOutput(source, moduleName: "CPointerToLongWrapper", expected: "0\n")
    }

    @Test
    func testCPointerToLongReturnTypeIsLong() throws {
        let source = """
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.toLong

        fun main() {
            val nullPtr: CPointer<ByteVar>? = null
            val addr: Long = nullPtr.toLong()
            println(addr == 0L)
        }
        """

        try assertKotlinOutput(source, moduleName: "CPointerToLongReturnType", expected: "true\n")
    }
}
#endif
