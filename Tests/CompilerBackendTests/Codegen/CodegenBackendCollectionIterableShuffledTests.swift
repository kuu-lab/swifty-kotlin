@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionIterableShuffledTests {
    private func runCodegenPipeline(
        inputPath: String,
        moduleName: String,
        outputPath: String
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple(),
            stdlibLibraryPath: try testStdlibArtifactPath()
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
    func testCodegenIterableShuffledPreservesSemantics() throws {
        let source = """
        import kotlin.random.Random

        class OneShotIterable<T>(private val values: List<T>) : Iterable<T> {
            var iteratorCalls = 0

            override fun iterator(): Iterator<T> {
                iteratorCalls += 1
                if (iteratorCalls > 1) throw IllegalStateException("iterated more than once")
                return values.iterator()
            }
        }

        fun sameIntMultiset(values: List<Int>, expected: List<Int>): Boolean {
            return values.size == expected.size &&
                values.count { it == 1 } == expected.count { it == 1 } &&
                values.count { it == 2 } == expected.count { it == 2 } &&
                values.count { it == 3 } == expected.count { it == 3 } &&
                values.count { it == 5 } == expected.count { it == 5 }
        }

        fun main() {
            val original = listOf(1, 1, 2, 3, 5)
            val iterable: Iterable<Int> = original

            val defaultResult = iterable.shuffled()
            println(defaultResult.size)
            println(sameIntMultiset(defaultResult, original))
            println(defaultResult !== iterable)
            println(original == listOf(1, 1, 2, 3, 5))

            val seededOne = iterable.shuffled(Random(42))
            val seededTwo = iterable.shuffled(Random(42))
            println(seededOne)
            println(seededOne == seededTwo)
            println(sameIntMultiset(seededOne, original))
            println(sameIntMultiset(iterable.shuffled(Random(43)), original))

            val empty: Iterable<Int> = emptyList()
            println(empty.shuffled(Random(42)).size)
            val singleton: Iterable<Int> = listOf(42)
            println(singleton.shuffled(Random(42)))

            val nullable: Iterable<String?> = listOf("a", null, "a")
            val nullableResult = nullable.shuffled(Random(42))
            println(nullableResult.size)
            println(nullableResult.count { it == null })
            println(nullableResult.count { it == "a" })

            val oneShotDefault = OneShotIterable(listOf(4, 5, 6))
            val defaultOneShotResult = oneShotDefault.shuffled()
            println(defaultOneShotResult.size)
            println(oneShotDefault.iteratorCalls)

            val oneShotSeeded = OneShotIterable(listOf(7, 8, 9))
            val seededOneShotResult = oneShotSeeded.shuffled(Random(42))
            println(seededOneShotResult)
            println(oneShotSeeded.iteratorCalls)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CollectionIterableShuffled",
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(
                normalizedStdout == """
                5
                true
                true
                true
                [1, 5, 2, 1, 3]
                true
                true
                true
                0
                [42]
                3
                1
                2
                3
                1
                [8, 7, 9]
                1
                """ + "\n"
            )
        }
    }
}
#endif
