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
struct CodegenBackendCollectionWindowedTransformEdgeCasesTests {

    @Test
    func testCodegenCollectionWindowedNonTransformOverloads() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3, 4, 5)
            println(list.windowed(3))
            println(list.windowed(3, 2))
            println(list.windowed(3, 2, true))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionWindowedNonTransformOverloads",
            expected:
                """
                [[1, 2, 3], [2, 3, 4], [3, 4, 5]]
                [[1, 2, 3], [3, 4, 5]]
                [[1, 2, 3], [3, 4, 5], [5]]
                """
                + "\n"
        )
    }

    @Test
    func testCodegenCollectionWindowedHandlesCollectionAndSetReceivers() throws {
        let source = """
        fun main() {
            val collection: Collection<Int> = setOf(1, 2, 3, 4)
            println(collection.windowed(2))
            println(collection.windowed(3, 2, true))

            val set = setOf(4, 5, 6)
            println(set.windowed(2))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionWindowedCollectionReceivers",
            expected:
                """
                [[1, 2], [2, 3], [3, 4]]
                [[1, 2, 3], [3, 4]]
                [[4, 5], [5, 6]]
                """
                + "\n"
        )
    }

    @Test
    func testCodegenCollectionWindowedTransformEdgeCases() throws {
        let source = """
        fun main() {
            val list = listOf(1, 2, 3, 4, 5)
            println(list.windowed(3, 2, true) { window -> window.size })
            println(list.windowed(3, 2, false) { window -> window.joinToString("-") })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionWindowedTransformEdgeCases",
            expected:
                """
                [3, 3, 1]
                [1-2-3, 3-4-5]
                """
                + "\n"
        )
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
}
#endif
