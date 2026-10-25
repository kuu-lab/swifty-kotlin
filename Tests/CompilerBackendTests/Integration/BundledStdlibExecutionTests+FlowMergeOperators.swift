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
                println(merge(flowOf(1, 2), flowOf(3, 4)).toList().sorted())
                println(listOf(flowOf(1, 2), flowOf(3, 4)).merge().toList().sorted())
                println(flow<Int> { emit(4); emit(3); emit(2); emit(1) }.toList().sorted())
                println(listOf(flowOf(2, 1)).merge().toList().sorted())
                println(listOf(flowOf(1, 3, 2)).merge().toList().sortedDescending())
                println(emptyList<Flow<Int>>().merge().toList())
                println(flowOf(flowOf(1, 2), flowOf(3, 4)).flattenMerge().toList().sorted())
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
            [1, 2, 3, 4]
            [1, 2, 3, 4]
            [1, 2]
            [3, 2, 1]
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
    func testFlowMergeOperatorsCollectConcurrentlyAndLimitConcurrency(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.channels.Channel
            import kotlinx.coroutines.channels.tryReceive
            import kotlinx.coroutines.flow.*

            fun gated(value: Int, started: Channel<Unit>, proceed: Channel<Unit>): Flow<Int> = flow {
                emit(value)
                started.send(Unit)
                proceed.receive()
                emit(value + 10)
            }

            suspend fun verifyConcurrent(
                factory: (Channel<Unit>, Channel<Unit>) -> Flow<Int>
            ): String = coroutineScope {
                val started = Channel<Unit>(0)
                val proceed = Channel<Unit>(0)
                val release = launch {
                    started.receive()
                    started.receive()
                    proceed.send(Unit)
                    proceed.send(Unit)
                }
                val values = withTimeout(2_000) { factory(started, proceed).toList() }
                release.join()
                var checksum = 0
                for (value in values) checksum += value
                "${values.size}:$checksum"
            }

            fun main() = runBlocking {
                println(verifyConcurrent { started, proceed ->
                    flowOf(gated(1, started, proceed), gated(2, started, proceed)).flattenMerge(2)
                })
                println(verifyConcurrent { started, proceed ->
                    flowOf(1, 2).flatMapMerge(2) { value -> gated(value, started, proceed) }
                })
                println(verifyConcurrent { started, proceed ->
                    listOf(gated(1, started, proceed), gated(2, started, proceed)).merge()
                })
                println(verifyConcurrent { started, proceed ->
                    merge(gated(1, started, proceed), gated(2, started, proceed))
                })

                val starts = Channel<Int>(Channel.UNLIMITED)
                val proceed = Channel<Unit>(Channel.UNLIMITED)
                var exceededLimit = false
                val limited = flowOf(1, 2, 3).flatMapMerge(2) { value ->
                    flow {
                        starts.send(value)
                        proceed.receive()
                        emit(value)
                    }
                }
                val controller = launch {
                    starts.receive()
                    starts.receive()
                    exceededLimit = starts.tryReceive().isSuccess
                    proceed.send(Unit)
                    starts.receive()
                    proceed.send(Unit)
                    proceed.send(Unit)
                }
                val limitedValues = withTimeout(2_000) { limited.toList() }
                controller.join()
                var limitedSum = 0
                for (value in limitedValues) limitedSum += value
                println("$exceededLimit:${limitedValues.size}:$limitedSum")

                val entered = Channel<Unit>(0)
                val never = Channel<Unit>(0)
                val cancelled = Channel<Unit>(Channel.UNLIMITED)
                val failing = flowOf(1, 2).flatMapMerge(2) { value ->
                    if (value == 1) {
                        flow {
                            try {
                                entered.send(Unit)
                                never.receive()
                            } finally {
                                cancelled.trySend(Unit)
                            }
                        }
                    } else {
                        flow {
                            entered.receive()
                            throw IllegalStateException("inner failed")
                        }
                    }
                }
                var failureMessage = "none"
                try {
                    withTimeout(2_000) { failing.toList() }
                } catch (failure: IllegalStateException) {
                    failureMessage = failure.message ?: "missing message"
                }
                println("$failureMessage:${cancelled.tryReceive().isSuccess}")
            }
            """,
            expectedOutput: """
            4:26
            4:26
            4:26
            4:26
            false:3:6
            inner failed:true

            """,
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowCombineTransformOperators(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.channels.Channel
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                // Use explicitly typed transform values because lambda literals
                // cannot yet be checked against a FlowCollector-receiver parameter at a call
                // site (KUU-1378 builder-inference gap).
                val pairSum: suspend FlowCollector<Int>.(Int, Int) -> Unit = { a, b -> emit(a + b) }
                println(flowOf(1).combineTransform(flowOf(2), pairSum).toList())
                val pairTwice: suspend FlowCollector<Int>.(Int, Int) -> Unit = { a, b -> emit(0); emit(a + b) }
                println(flowOf(1).combineTransform(flowOf(2), pairTwice).toList())
                val pairDash: suspend FlowCollector<String>.(Int, Int) -> Unit = { a, b -> emit("$a-$b") }
                val pairCombined = flowOf(1, 2).combineTransform(flowOf(3), pairDash).toList()
                println(pairCombined.last())
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
                val iterableCombined = combineTransform(listOf(flowOf(1, 2), flowOf(3, 4)), arraySum).toList()
                println(iterableCombined.last())
                // An empty input flow yields no emissions.
                println(combineTransform(listOf(flowOf(1), emptyFlow<Int>()), arraySum).toList())

                val leftReady = Channel<Unit>(0)
                val allowLeftUpdate = Channel<Unit>(0)
                val leftUpdated = Channel<Unit>(0)
                val liveLeft = flow {
                    emit(1)
                    leftReady.send(Unit)
                    allowLeftUpdate.receive()
                    emit(2)
                    leftUpdated.send(Unit)
                }
                val liveRight = flow {
                    leftReady.receive()
                    emit(10)
                    allowLeftUpdate.send(Unit)
                    leftUpdated.receive()
                    emit(20)
                }
                println(liveLeft.combineTransform(liveRight, pairDash).toList())
            }
            """,
            expectedOutput: """
            [3]
            [0, 3]
            2-3
            [6]
            [10]
            [15]
            [3]
            6
            []
            [1-10, 2-10, 2-20]

            """,
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowCombineAndZipCancellation(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                var infinitePeerCancelled = false
                val infiniteFlow = flow<Int> {
                    try {
                        while (true) emit(1)
                    } finally {
                        infinitePeerCancelled = true
                    }
                }

                println(infiniteFlow.zip(flowOf(10, 20)) { left, right -> left + right }.toList())
                println(infinitePeerCancelled)
                infinitePeerCancelled = false
                println(flowOf(100, 200).zip(infiniteFlow) { left, right -> left + right }.toList())
                println(infinitePeerCancelled)
                infinitePeerCancelled = false
                println(infiniteFlow.combine(flowOf(10)) { left, right -> left + right }.take(3).toList())
                println(infinitePeerCancelled)
                infinitePeerCancelled = false
                println(infiniteFlow.combine(emptyFlow<Int>()) { left, right -> left + right }.toList())
                println(infinitePeerCancelled)

                infinitePeerCancelled = false
                try {
                    infiniteFlow.combine(flowOf(10)) { _, _ ->
                        throw IllegalStateException("transform")
                    }.toList()
                } catch (failure: IllegalStateException) {
                    println(failure.message)
                }
                println(infinitePeerCancelled)

                infinitePeerCancelled = false
                try {
                    flowOf(1, 2).zip(infiniteFlow) { _, _ ->
                        throw IllegalStateException("zip transform")
                    }.toList()
                } catch (failure: IllegalStateException) {
                    println(failure.message)
                }
                println(infinitePeerCancelled)
            }
            """,
            expectedOutput: "[11, 21]\ntrue\n[101, 201]\ntrue\n[11, 11, 11]\ntrue\n[]\ntrue\ntransform\ntrue\nzip transform\ntrue\n",
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

    @Test(arguments: [true, false])
    func testFlowFlatMapOperators(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*

            fun makePipeline(source: Flow<Int>): Flow<String> {
                return source
                    .flatMapConcat { v ->
                        flow {
                            emit("a-$v")
                            emit("b-$v")
                        }
                    }
                    .map { "mapped-$it" }
            }

            fun main() = runBlocking {
                // 1. Cold semantics verification (KUU-1350):
                // Transform must not run at construction time (touched == 0).
                var touched = 0
                val coldFlow = flowOf(1, 2).flatMapConcat {
                    touched++
                    flowOf(it * 10)
                }
                println("touched before: $touched")
                println(coldFlow.toList())
                println("touched after: $touched")

                // 2. Non-suspend pipeline composition
                val pipeline = makePipeline(flowOf(1, 2))
                println(pipeline.toList())

                // 3. flatMapMerge with default concurrency and custom concurrency
                println(flowOf(1, 2).flatMapMerge { flowOf(it, it * 100) }.toList().sorted())
                println(flowOf(1, 2).flatMapMerge(2) { flowOf(it, it * 100) }.toList().sorted())
                println(flowOf(1, 2).flatMapMerge(1) { flowOf(it, it * 100) }.toList())
                try {
                    flowOf(1).flatMapMerge(0) { flowOf(it) }.toList()
                } catch (e: IllegalArgumentException) {
                    println("invalid concurrency")
                }

                // 4. flatMapLatest
                println(flowOf(1, 2).flatMapLatest { flowOf(it * 5) }.toList())
            }
            """,
            expectedOutput: """
            touched before: 0
            [10, 20]
            touched after: 2
            [mapped-a-1, mapped-b-1, mapped-a-2, mapped-b-2]
            [1, 2, 100, 200]
            [1, 2, 100, 200]
            [1, 100, 2, 200]
            invalid concurrency
            [5, 10]

            """,
            allowDefaultStdlibLibrary: artifact
        )
    }
}
