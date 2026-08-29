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
struct CodegenBackendStringToListTests {

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
    func testCodegenStringToList() throws {
        let source = """
        fun main() {
            // String literal receiver
            println("hello".toList())

            // empty string yields an empty list
            println("".toList())

            // CharSequence receiver resolves to the same conversion
            val cs: CharSequence = "abc"
            println(cs.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringToList",
            expected:
                """
                [h, e, l, l, o]
                []
                [a, b, c]
                """
                + "\n"
        )
    }

    @Test
    func testCodegenStringToListSupportsListOperations() throws {
        // The result is a genuine List<Char>, so size/first/last behave as expected.
        // (Indexing via chars[0] is intentionally avoided here: the get-operator
        // lowering mis-dispatches List<Char>[i] to kk_string_get — a pre-existing
        // bug unrelated to toList, reproducible with listOf('h','i')[0].)
        let source = """
        fun main() {
            val chars = "hi".toList()
            println(chars.size)
            println(chars.first())
            println(chars.last())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "StringToListOps",
            expected:
                """
                2
                h
                i
                """
                + "\n"
        )
    }

    @Test
    func testCodegenCharSequenceCollectionConversionsUseSourceIterator() throws {
        let source = """
        fun main() {
            val text: CharSequence = "caba"

            val iterator = text.iterator()
            println(iterator.next())

            var iterated = 0
            for (character in text) iterated++
            println(iterated)

            println(text.asIterable().toList().size)
            println(text.asSequence().toList())
            println(text.toMutableList().size)
            println(text.toCharArray().size)
            println(text.toTypedArray().size)

            val destination = mutableListOf<Char>('!')
            println(text.toCollection(destination))
            println(text.toSortedSet())
            println(text.withIndex().toList().size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CharSequenceCollectionConversions",
            expected:
                """
                c
                4
                4
                [c, a, b, a]
                4
                4
                4
                [!, c, a, b, a]
                [a, b, c]
                4
                """
                + "\n"
        )
    }
}
#endif
