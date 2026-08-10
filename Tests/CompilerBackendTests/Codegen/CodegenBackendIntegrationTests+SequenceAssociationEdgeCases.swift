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
struct CodegenBackendSequenceAssociationEdgeCasesTests {

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
    func testSequenceAssociateBuildsMapWithUniqueKeys() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3).associate { it to it * 10 }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceAssociateUniqueKeys", expected: "{1=10, 2=20, 3=30}\n")
    }

    @Test
    func testSequenceAssociateEmptySequenceReturnsEmptyMap() throws {
        let source = """
        fun main() {
            val result = emptySequence<Int>().associate { it to it * 10 }
            println(result)
            println(result.size)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceAssociateEmptySeq", expected: "{}\n0\n")
    }

    @Test
    func testSequenceAssociateWithStringElementsProducesStringIntMap() throws {
        let source = """
        fun main() {
            val result = sequenceOf("a", "bb", "ccc").associate { it to it.length }
            println(result["a"])
            println(result["bb"])
            println(result["ccc"])
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceAssociateStringKeys", expected: "1\n2\n3\n")
    }

    @Test
    func testSequenceAssociateAllowsKeyLookupInResult() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3).associate { it to it * it }
            println(result[1])
            println(result[2])
            println(result[3])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceAssociateKeyLookup",
            expected:
                """
                1
                4
                9
                """ + "\n"
        )
    }

    @Test
    func testSequenceAssociateWithMapsElementsToTransformedValues() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3).associateWith { value ->
                value * value
            }
            println(result[1])
            println(result[2])
            println(result[3])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceAssociateWithRuntime",
            expected:
                """
                1
                4
                9
                """ + "\n"
        )
    }
}
#endif
