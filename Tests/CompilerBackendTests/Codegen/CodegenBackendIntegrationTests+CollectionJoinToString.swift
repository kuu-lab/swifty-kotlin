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
struct CodegenBackendCollectionJoinToStringTests {
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

    // Keep all joinToString coverage in one test method. This test case is
    // already large, and Swift's generated Linux discovery array can exceed
    // the type-checker time limit when several methods are added.
    @Test func testCodegenIterableJoinToStringUsesRuntimeDefaultsAndNamedArguments() throws {
        let source = """
        fun main() {
            val collection: Collection<Int> = listOf(1, 2, 3)
            println(collection.joinToString())
            println(collection.joinToString(" | "))
            println(collection.joinToString(prefix = "<", postfix = ">"))
            println(collection.joinToString(separator = ":", prefix = "[", postfix = "]"))

            val set: Set<String> = setOf("x", "y")
            println(set.joinToString(";"))

            val parts = "a\\r\\nbb\\r\\nccc".split("\\r\\n")
            println(parts.joinToString(",") { it.length.toString() })

            val list = listOf("a", "bb", "ccc")
            println(list.joinToString { it.length.toString() })
            println(list.joinToString(",", "[", "]") { it.length.toString() })

            val empty = emptyList<String>()
            println(empty.joinToString { it.length.toString() })

            val iter: Iterable<String> = listOf("a", "bb", "ccc")
            println(iter.joinToString("-") { "<" + it + ">" })

            // Named-argument calls without a transform must keep resolving to
            // the plain (separator, prefix, postfix) overload.
            println(list.joinToString(prefix = "<", postfix = ">"))

            try {
                println(listOf(1, 2, 3).joinToString(",") {
                    if (it == 2) throw IllegalStateException("boom")
                    it.toString()
                })
                println("missing-throw")
            } catch (e: IllegalStateException) {
                println("caught: " + e.message)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IterableAndListJoinToStringRuntime",
            expected:
                """
                1, 2, 3
                1 | 2 | 3
                <1, 2, 3>
                [1:2:3]
                x;y
                1,2,3
                1, 2, 3
                [1,2,3]

                <a>-<bb>-<ccc>
                <a, bb, ccc>
                caught: boom
                """ + "\n"
        )
    }
}
#endif
