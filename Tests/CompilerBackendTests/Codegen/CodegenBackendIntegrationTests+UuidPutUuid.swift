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
struct CodegenBackendUuidPutUuidTests {

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
    func testCodegenUuidAtReadsNilUuidFromByteBuffer() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid
        import kotlin.uuid.getUuid
        import java.nio.ByteBuffer

        fun main() {
            val nilBytes = Uuid.NIL.toByteArray()
            val buf = ByteBuffer.wrap(nilBytes)
            val readback = buf.getUuid(0)
            println(readback.toString())
        }
        """
        try assertKotlinOutput(source, moduleName: "UuidAtReadsNilUuid", expected: "00000000-0000-0000-0000-000000000000\n")
    }

    @Test
    func testCodegenUuidPutUuidRoundTripPreservesValue() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid
        import kotlin.uuid.putUuid
        import kotlin.uuid.getUuid
        import java.nio.ByteBuffer

        fun main() {
            val original = Uuid.fromLongs(0L, 1L)
            val buf = ByteBuffer.wrap(Uuid.NIL.toByteArray())
            buf.putUuid(0, original)
            val readback = buf.getUuid(0)
            println(readback.toString())
        }
        """
        try assertKotlinOutput(source, moduleName: "UuidPutUuidRoundTrip", expected: "00000000-0000-0000-0000-000000000001\n")
    }

    @Test
    func testCodegenUuidPutUuidOverwritesBuffer() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid
        import kotlin.uuid.putUuid
        import kotlin.uuid.getUuid
        import java.nio.ByteBuffer

        fun main() {
            val uuid = Uuid.fromLongs(0x0102030405060708L, 0x090a0b0c0d0e0f10L)
            val buf = ByteBuffer.wrap(Uuid.NIL.toByteArray())
            buf.putUuid(0, uuid)
            println(buf.get(0))
            println(buf.get(15))
            val readback = buf.getUuid(0)
            println(readback.toString())
        }
        """
        try assertKotlinOutput(source, moduleName: "UuidPutUuidOverwritesBuffer", expected: "1\n16\n01020304-0506-0708-090a-0b0c0d0e0f10\n")
    }
}
#endif
