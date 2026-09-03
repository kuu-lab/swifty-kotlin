#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func runCodegenPipeline(
    inputPath: String,
    moduleName: String,
    emit: EmitMode,
    outputPath: String
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
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
struct CodegenBackendMutableIterablePredicateTests {

    @Test
    func testCodegenMutableIterablePredicateOperationsMutateRuntimeCollections() throws {
        let source = """
        class TrackingIterator(private val values: ArrayList<Int>) : MutableIterator<Int> {
            private var index = 0

            override fun hasNext(): Boolean = index < values.size

            override fun next(): Int = values[index++]

            override fun remove() {
                values.removeAt(--index)
            }
        }

        class TrackingIterable(private val values: ArrayList<Int>) : MutableIterable<Int> {
            override fun iterator(): MutableIterator<Int> = TrackingIterator(values)
        }

        fun main() {
            val list = mutableListOf(1, 2, 3)
            val listIterable: MutableIterable<Int> = list
            println(listIterable.removeAll { it == 2 })
            println(list)

            val set = mutableSetOf(1, 2, 3)
            val setIterable: MutableIterable<Int> = set
            println(setIterable.retainAll { it != 2 })
            println(set)

            val customValues = arrayListOf(1, 2, 3)
            println(TrackingIterable(customValues).removeAll { it == 2 })
            println(customValues)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MutableIterablePredicate",
            expected:
                """
                true
                [1, 3]
                true
                [1, 3]
                true
                [1, 3]
                """ + "\n"
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
