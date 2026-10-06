import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testFlowFlattenAndMergeOperators(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                println(flowOf(flowOf(1, 2), flowOf(3, 4)).flattenConcat().toList())
                println(flowOf(flowOf(1), emptyFlow<Int>(), flowOf(2)).flattenConcat().toList())
                println(emptyFlow<Flow<Int>>().flattenConcat().toList())
                // Sequential cold-flow model: merge collects each flow in order.
                println(listOf(flowOf(1, 2), flowOf(3, 4)).merge().toList())
                println(emptyList<Flow<Int>>().merge().toList())
                println(flowOf(flowOf(1, 2), flowOf(3, 4)).flattenMerge().toList())
                println(flowOf(flowOf(1, 2), flowOf(3, 4)).flattenMerge(1).toList())
                try {
                    flowOf(flowOf(1)).flattenMerge(0).toList()
                } catch (e: IllegalArgumentException) {
                    println("flattenMerge(0)")
                }
                println(DEFAULT_CONCURRENCY > 0)
            }
            """,
            expectedOutput: """
            [1, 2, 3, 4]
            [1, 2]
            []
            [1, 2, 3, 4]
            []
            [1, 2, 3, 4]
            [1, 2, 3, 4]
            flattenMerge(0)
            true

            """,
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowCombineTransformOperators(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                // Sequential snapshot model: transform runs on indexed tuples,
                // shorter flows retain their last value. Transforms are bound
                // through explicitly-typed vals: a lambda literal cannot yet be
                // checked against a FlowCollector-receiver parameter at a call
                // site (KUU-1378 builder-inference gap).
                val pairSum: suspend FlowCollector<Int>.(Int, Int) -> Unit = { a, b -> emit(a + b) }
                println(flowOf(1).combineTransform(flowOf(2), pairSum).toList())
                val pairTwice: suspend FlowCollector<Int>.(Int, Int) -> Unit = { a, b -> emit(0); emit(a + b) }
                println(flowOf(1).combineTransform(flowOf(2), pairTwice).toList())
                val pairDash: suspend FlowCollector<String>.(Int, Int) -> Unit = { a, b -> emit("$a-$b") }
                println(flowOf(1, 2).combineTransform(flowOf(3), pairDash).toList())
                val tripleSum: suspend FlowCollector<Int>.(Int, Int, Int) -> Unit =
                    { a, b, c -> emit(a + b + c) }
                println(combineTransform(flowOf(1), flowOf(2), flowOf(3), tripleSum).toList())
                val quadSum: suspend FlowCollector<Int>.(Int, Int, Int, Int) -> Unit =
                    { a, b, c, d -> emit(a + b + c + d) }
                println(
                    combineTransform(flowOf(1), flowOf(2), flowOf(3), flowOf(4), quadSum).toList()
                )
                val quintSum: suspend FlowCollector<Int>.(Int, Int, Int, Int, Int) -> Unit =
                    { a, b, c, d, e -> emit(a + b + c + d + e) }
                println(
                    combineTransform(flowOf(1), flowOf(2), flowOf(3), flowOf(4), flowOf(5), quintSum).toList()
                )
                val arraySum: suspend FlowCollector<Int>.(Array<Int>) -> Unit =
                    { values -> emit(values.sum()) }
                println(combineTransform(flowOf(1), flowOf(2), transform = arraySum).toList())
                println(combineTransform(listOf(flowOf(1, 2), flowOf(3, 4)), arraySum).toList())
                // An empty input flow yields no emissions.
                println(combineTransform(listOf(flowOf(1), emptyFlow<Int>()), arraySum).toList())
            }
            """,
            expectedOutput: """
            [3]
            [0, 3]
            [1-3, 2-3]
            [6]
            [10]
            [15]
            [3]
            [4, 6]
            []

            """,
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowChunkedWindowedOperators(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                println(flowOf(1, 2, 3, 4, 5).chunked(2).toList())
                println(flowOf(1, 2).chunked(5).toList())
                println(emptyFlow<Int>().chunked(2).toList())
                try {
                    flowOf(1).chunked(0).toList()
                } catch (e: IllegalArgumentException) {
                    println("chunked(0)")
                }
                // KSwiftK-only compat surface (not a real upstream Flow operator):
                // semantics match kotlin.collections.Iterable.windowed.
                println(flowOf(1, 2, 3).windowed(2).toList())
                println(flowOf(1, 2, 3, 4, 5).windowed(3, step = 2, partialWindows = true).toList())
                // partialWindows defaults to false: the trailing partial window
                // [5] is dropped, matching kotlin.collections.Iterable.windowed.
                println(flowOf(1, 2, 3, 4, 5).windowed(3, step = 2) { it.sum() }.toList())
            }
            """,
            expectedOutput: """
            [[1, 2], [3, 4], [5]]
            [[1, 2]]
            []
            chunked(0)
            [[1, 2], [2, 3]]
            [[1, 2, 3], [3, 4, 5], [5]]
            [6, 12]

            """,
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowTimeoutAndFlowWith(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.TimeoutCancellationException
            import kotlinx.coroutines.delay
            import kotlinx.coroutines.flow.*
            import kotlin.time.Duration
            import kotlin.time.Duration.Companion.milliseconds
            import kotlin.time.Duration.Companion.seconds

            fun main() = runBlocking {
                println(flowOf(1, 2).timeout(10.seconds).toList())
                try {
                    flow<Int> {
                        emit(1)
                        delay(200)
                        emit(2)
                    }.timeout(50.milliseconds).toList()
                } catch (e: TimeoutCancellationException) {
                    println("timed out")
                }
                try {
                    flowOf(1).timeout(Duration.ZERO).toList()
                } catch (e: TimeoutCancellationException) {
                    println("immediate")
                }
                // Compat pass-through: flowWith was removed upstream; in the
                // sequential cold-flow model it reduces to flowOn/this.
                println(flowOf(7).flowWith(coroutineContext).toList())
            }
            """,
            expectedOutput: """
            [1, 2]
            timed out
            immediate
            [7]

            """,
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowAsFlowOverloads(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                println(intArrayOf(1, 2).asFlow().toList())
                println(intArrayOf(1, 2).asFlow().map { it * 10 }.toList())
                println(longArrayOf(3L, 4L).asFlow().toList())
                println(arrayOf(5, 6).asFlow().toList())
                println(listOf(7, 8).iterator().asFlow().toList())
                println(sequenceOf(9).asFlow().toList())
                println(listOf(10, 11).asFlow().toList())
                val makeInt: () -> Int = { 12 }
                println(makeInt.asFlow().toList())
                val fetchInt: suspend () -> Int = { 13 }
                println(fetchInt.asFlow().toList())
            }
            """,
            expectedOutput: """
            [1, 2]
            [10, 20]
            [3, 4]
            [5, 6]
            [7, 8]
            [9]
            [10, 11]
            [12]
            [13]

            """,
            allowDefaultStdlibLibrary: artifact
        )
    }
}
