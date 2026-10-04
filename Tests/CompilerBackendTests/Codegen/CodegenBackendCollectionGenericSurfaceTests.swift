@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

private func runCollectionGenericSurfaceCodegenPipeline(
    inputPath: String,
    moduleName: String,
    outputPath: String
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: .executable,
        target: defaultTargetTriple()
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    try CodegenPhase().run(ctx)
    return ctx
}

@Suite
struct CodegenBackendCollectionGenericSurfaceTests {
    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCollectionGenericSurfaceCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    // KSP-435: `any`/`all`/`last` on a bare `Collection<T>` / `Iterable<T>`
    // receiver must bind the bundled `kotlin.collections` source. Before the
    // fix the calls stayed unresolved and the linker failed with
    // "undefined reference to 'any'".
    @Test
    func codegenCollectionGenericMembersUseBundledSource() throws {
        let source = """
        fun main() {
            val collection: Collection<Int> = listOf(1, 2, 3)
            println(collection.any())
            println(collection.all { it > 0 })
            println(collection.last())
            println(collection.toList())
            println(collection.size)
            println(collection.isEmpty())
            println(collection.toTypedArray().size)
            println(collection.toCollection(mutableListOf(0)))

            val iterable: Iterable<String> = setOf("x", "y")
            println(iterable.any { it == "y" })
            println(iterable.last())
            println(iterable.toMutableList().size)

            val set: Collection<String> = setOf("p", "q", "r")
            println(set.size)
            println(set.joinToString(prefix = "<", postfix = ">"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionGenericSurface",
            expected: """
            true
            true
            3
            [1, 2, 3]
            3
            false
            3
            [0, 1, 2, 3]
            true
            y
            2
            3
            <p, q, r>

            """
        )
    }
}
#endif
