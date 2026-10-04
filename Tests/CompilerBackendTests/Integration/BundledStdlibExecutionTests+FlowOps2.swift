import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testFlowOps2SampleCompletionAndValidation(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*
            import kotlin.time.*

            fun main() = runBlocking {
                val sampled = flowOf(1, 2, 3).sample(100L)
                println(sampled.toList())
                println(sampled.toList())
                println(emptyFlow<Int>().sample(1L).toList())
                println(flowOf<Int?>(1, null).sample(1L).toList())
                println(flowOf(4, 5).sample(10.toDuration(DurationUnit.MILLISECONDS)).toList())
                println(flowOf(6).sample(1.toDuration(DurationUnit.NANOSECONDS)).toList())
                try {
                    flowOf(1).sample(0L)
                } catch (e: IllegalArgumentException) {
                    println(e.message)
                }
                try {
                    flowOf(1).sample((-1).toDuration(DurationUnit.MILLISECONDS))
                } catch (e: IllegalArgumentException) {
                    println(e.message)
                }
                println("done")
            }
            """,
            expectedOutput: "[3]\n[3]\n[]\n[null]\n[5]\n[6]\nSample period should be positive\nSample period should be positive\ndone\n",
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowOps2CombineSequentialSnapshots(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val combined = combine(flowOf(1, 2, 3), flowOf(10), flowOf(100, 200)) { values: Array<Int> ->
                    values.sum()
                }
                println(combined.toList())
                println(combined.toList())
                println(flowOf(1, 2).combineLatest(flowOf(10), flowOf(100)) { a, b, c -> a + b + c }.toList())
                println(combine(flowOf<Int?>(null), flowOf<Int?>(1)) { values: Array<Int?> -> values.toList() }.toList())
            }
            """,
            expectedOutput: "[111, 212, 213]\n[111, 212, 213]\n[111, 112]\n[[null, 1]]\n",
            allowDefaultStdlibLibrary: artifact
        )
    }
}
