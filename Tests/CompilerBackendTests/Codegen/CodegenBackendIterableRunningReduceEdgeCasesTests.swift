#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func runIterableRunningReduceCodegen(
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
    let context = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(context)
    try LoweringPhase().run(context)
    try CodegenPhase().run(context)
    return context
}

@Suite(.serialized)
struct CodegenBackendIterableRunningReduceEdgeCasesTests {
    @Test
    func testIterableRunningReduceUsesSourceBackedGenericOverloads() throws {
        let source = """
        class CountingIterator(private val limit: Int) : Iterator<Int> {
            private var current = 0

            override fun hasNext(): Boolean = current < limit

            override fun next(): Int {
                if (current >= limit) throw IllegalStateException("over-consumed")
                val value = current
                current += 1
                return value
            }
        }

        class CountingIterable(private val limit: Int) : Iterable<Int> {
            override fun iterator(): Iterator<Int> = CountingIterator(limit)
        }

        fun failOnTwo(value: Int): Int {
            if (value == 2) throw IllegalStateException("stop")
            return value
        }

        fun main() {
            val widened: Iterable<Int> = listOf(1, 2, 3)
            println(widened.runningReduce { acc, value -> acc + value })
            println(widened.runningReduceIndexed { index, acc, value -> acc + index + value })
            println(emptyList<Int>().runningReduce { acc, value -> acc + value })
            val singleton: Iterable<Int> = listOf(42)
            println(singleton.runningReduce { acc, value -> acc + value })

            val nullable: Iterable<String?> = listOf("a", null, "b")
            println(nullable.runningReduce { acc, value -> (acc ?: "") + (value ?: "") })

            val widenedAccumulator: Iterable<String> = listOf("a", "b")
            println(widenedAccumulator.runningReduce { acc: Any?, value -> acc.toString() + value })

            var calls = 0
            println(widened.runningReduce { acc, value ->
                calls += 1
                acc + value
            })
            println("calls=$calls")

            try {
                val oneShot: Iterable<Int> = CountingIterable(5)
                val stopped: List<Int> = oneShot.runningReduceIndexed { index, acc, value ->
                    println("operation:$index:$value")
                    acc + failOnTwo(value)
                }
                println(stopped)
            } catch (e: IllegalStateException) {
                println(e.message)
            }

            println(listOf(1, 2, 3).runningReduce { acc, value -> acc + value })
            println(listOf(1, 2, 3).asSequence().runningReduce { acc, value -> acc + value }.toList())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let context = try runIterableRunningReduceCodegen(
                inputPath: path,
                moduleName: "IterableRunningReduceEdgeCases",
                outputPath: outputBase
            )
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(
                normalizedStdout == """
                [1, 3, 6]
                [1, 4, 9]
                []
                [42]
                [a, a, ab]
                [a, ab]
                [1, 3, 6]
                calls=2
                operation:1:1
                operation:2:2
                stop
                [1, 3, 6]
                [1, 3, 6]
                """ + "\n"
            )
        }
    }
}
#endif
