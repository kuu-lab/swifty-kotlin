import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testFlowTransformSuspendReceiverAndElementArguments(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.flow.*
            import kotlinx.coroutines.runBlocking

            fun main() = runBlocking {
                flowOf(1, 2).transform<Int, Int> { emit(it) }.collect { println(it) }
            }
            """,
            expectedOutput: "1\n2\n",
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testLoopCarriedFlowScopeOwnership(artifact: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("flow_loop_scope_ownership.kt", file: #filePath),
            expectedOutput: "scope finished\n1\n1\n1\nscope finished\n2\n2\ncollector failed\ncollector failed\n3\n",
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowCollectorFailureRecollectionInLoops(artifact: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kotlinx_coroutines_flow_caught_collector_loops.kt", file: #filePath),
            expectedOutput: """
            constructed
            repeat=0
            start
            value=1
            downstream
            repeat=1
            start
            value=1
            downstream
            for=0
            start
            value=1
            downstream
            for=1
            start
            value=1
            downstream
            success
            value=1
            value=2
            value=1
            value=2
            after

            """,
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowOps2DistinctRecollectionAndNulls(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val distinct = flowOf(1, 1, 2, 2, 1).distinctUntilChanged()
                println(distinct.toList())
                println(distinct.toList())
                println(flowOf<Int?>(null, null, 1, 1, null).distinctUntilChanged().toList())
                println(flowOf(1, 3, 2, 4, 1).distinctUntilChanged { a, b -> a % 2 == b % 2 }.toList())
                println(flowOf("a", "b", "cc", "dd", "e").distinctUntilChangedBy { it.length }.toList())
                println(flowOf(1, 2, 3).distinctUntilChangedBy { null }.toList())
                println(emptyFlow<Int>().distinctUntilChanged().toList())
            }
            """,
            expectedOutput: "[1, 2, 1]\n[1, 2, 1]\n[null, 1, null]\n[1, 2, 1]\n[a, cc, e]\n[1]\n[]\n",
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowOps2LatestTransforms(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val mapped = flowOf(1, 2, 3).mapLatest { it * 10 }
                println(mapped.toList())
                println(mapped.toList())
                val transformed = flowOf(1, 2, 3).transformLatest<Int, Int> { value ->
                    if (value != 2) {
                        emit(value)
                        emit(value * 10)
                    }
                }
                println(transformed.toList())
                println(transformed.toList())
                println(flowOf(1).conflate().toList())
                println(flowOf(1, 2).flatMapLatest { flowOf(it, it * 10) }.toList())
            }
            """,
            expectedOutput: "[10, 20, 30]\n[10, 20, 30]\n[1, 10, 3, 30]\n[1, 10, 3, 30]\n[1]\n[1, 10, 2, 20]\n",
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowBufferConflateAndFlowOn(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.coroutines.ContinuationInterceptor
            import kotlinx.coroutines.*
            import kotlinx.coroutines.channels.BufferOverflow
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val dropOldest = mutableListOf<Int>()
                flowOf(1, 2, 3, 4, 5)
                    .buffer(1, BufferOverflow.DROP_OLDEST)
                    .flowOn(Dispatchers.IO)
                    .collect { value: Int ->
                        delay(20L)
                        dropOldest.add(value)
                    }
                println(dropOldest)

                val dropLatest = mutableListOf<Int>()
                flowOf(1, 2, 3, 4, 5)
                    .buffer(1, BufferOverflow.DROP_LATEST)
                    .collect { value: Int ->
                        delay(20L)
                        dropLatest.add(value)
                    }
                println(dropLatest)

                val conflated = mutableListOf<Int>()
                flowOf(1, 2, 3, 4, 5)
                    .conflate()
                    .collect { value: Int ->
                        delay(20L)
                        conflated.add(value)
                    }
                println(conflated)

                var upstreamName = "missing"
                var upstreamUsesIO = false
                flow<Int> {
                    val context = currentCoroutineContext()
                    upstreamName = context[CoroutineName]?.name ?: "missing"
                    upstreamUsesIO = context[ContinuationInterceptor] === Dispatchers.IO
                    emit(9)
                }
                    .flowOn(Dispatchers.IO + CoroutineName("flow-upstream"))
                    .collect { }
                println("$upstreamName:$upstreamUsesIO")
            }
            """,
            expectedOutput: "[1, 5]\n[1, 2]\n[1, 5]\nflow-upstream:true\n",
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowLatestCancelsPreviousSuspendingWork(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.delay
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val collected = mutableListOf<Int>()
                flowOf(1, 2, 3).collectLatest { value ->
                    if (value < 3) delay(50)
                    collected.add(value)
                }
                println(collected)

                val mappedSideEffects = mutableListOf<Int>()
                val mapped = flowOf(1, 2, 3).mapLatest { value ->
                    if (value < 3) delay(50)
                    mappedSideEffects.add(value)
                    value
                }
                println(mapped.toList())
                println(mappedSideEffects)
            }
            """,
            expectedOutput: "[3]\n[3]\n[3]\n",
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowOps2ChannelConsumption(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.channels.*
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val channel = Channel<Int>(3)
                channel.send(1)
                channel.send(2)
                channel.close()
                val received = channel.receiveAsFlow()
                println(received.toList())
                println(received.toList())
                val consumed = Channel<String>(2)
                consumed.send("a")
                consumed.send("b")
                consumed.close()
                val once = consumed.consumeAsFlow()
                println(once.toList())
                try {
                    once.toList()
                } catch (e: IllegalStateException) {
                    println(e.message)
                }
            }
            """,
            expectedOutput: "[1, 2]\n[]\n[a, b]\nReceiveChannel.consumeAsFlow can be collected just once\n",
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowOps2SampleCompletionAndValidation(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*
            import kotlin.time.DurationUnit
            import kotlin.time.toDuration

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
    func testFlowOps2CombineLiveUpdates(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.channels.Channel
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val combined = combine(flowOf(1, 2, 3), flowOf(10), flowOf(100, 200)) { values: Array<Int> ->
                    values.toList().sum()
                }.toList()
                println(combined.size > 0)
                println(combined.last())
                val iterableCombined = combine(listOf(flowOf(1, 2), flowOf(3, 4))) { values: Array<Int> ->
                    values.toList().sum()
                }.toList()
                println(iterableCombined.last())
                println(combine(flowOf(2), flowOf(20)) { a, b -> a + b }.single())
                println(combine<Int, Int>(transform = { values: Array<Int> -> values.toList().sum() }).toList())
                println(combine(emptyList<Flow<Int>>()) { values: Array<Int> -> values.toList().sum() }.toList())
                val threeWayLatest = flowOf(1, 2).combineLatest(flowOf(10), flowOf(100)) { a, b, c -> a + b + c }.toList()
                println(threeWayLatest.size > 0)
                println(threeWayLatest.last())
                println(combine(flowOf(1), flowOf(2), flowOf(3)) { a, b, c -> a + b + c }.single())
                println(combine(flowOf(1), flowOf(2), flowOf(3), flowOf(4), flowOf(5)) { a, b, c, d, e -> a + b + c + d + e }.toList())
                println(combine(flowOf(1), flowOf(2), flowOf(3), flowOf(4)) { a, b, c, d -> a + b + c + d }.single())
                println(combine(flowOf<Int?>(null), flowOf<Int?>(1)) { values: Array<Int?> -> values.toList() }.toList())
                println(flowOf(2).combineLatest(flowOf("x")) { a, b -> "$a$b" }.toList())
                println(combine(flowOf(2), flowOf("x"), flowOf(true), flowOf(3.5), flowOf('z')) { a, b, c, d, e ->
                    "$a:$b:$c:$d:$e"
                }.toList())
                val suffix = "!"
                println(flowOf(2).combineLatest(flowOf("x"), flowOf(3)) { a, b, c -> "$a$b$c$suffix" }.toList())
                println(flowOf(1).combineLatest(flowOf(2), flowOf(3), flowOf(4)) { a, b, c, d -> a + b + c + d }.single())
                println(flowOf(1).combineLatest(flowOf(2), flowOf(3), flowOf(4), flowOf(5)) { a, b, c, d, e -> a + b + c + d + e }.single())

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
                println(liveLeft.combine(liveRight) { a, b -> a + b }.toList())
            }
            """,
            expectedOutput: "true\n213\n6\n22\n[]\n[]\ntrue\n112\n6\n[15]\n10\n[[null, 1]]\n[2x]\n[2:x:true:3.5:z]\n[2x3!]\n10\n15\n[11, 12, 22]\n",
            allowDefaultStdlibLibrary: artifact
        )
    }
}
