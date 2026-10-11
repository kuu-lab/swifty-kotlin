@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionLastTests {
    private func runExecutablePipeline(
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

    @Test
    func testCodegenIterableLastUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val map = mutableMapOf("k" to 1)
            println(map.values.first())
            println(map.values.last())

            val collection: Collection<Int> = listOf(1, 2, 3)
            println(collection.last())

            val iterable: Iterable<String> = setOf("x", "y")
            println(iterable.last())
        }
        """

        try assertKotlinOutput(source, moduleName: "IterableLastRuntime", expected: "1\n1\n3\ny\n")
    }
}
#endif
