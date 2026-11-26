import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testProducerScopeIsChecksMatchNominalInterfaces(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.channels.*
            import kotlinx.coroutines.flow.*

            fun printProducerScopeTypes(scope: ProducerScope<*>) {
                println(scope is CoroutineScope)
                println(scope is SendChannel<*>)
            }

            fun main() = runBlocking {
                callbackFlow<Int> {
                    printProducerScopeTypes(this)
                    close()
                }.collect { }
                channelFlow<Int> {
                    printProducerScopeTypes(this)
                    close()
                }.collect { }
                val producer = produce<Int> {
                    printProducerScopeTypes(this)
                    close()
                }
                producer.cancel()
            }
            """,
            expectedOutput: "true\ntrue\ntrue\ntrue\ntrue\ntrue\n",
            moduleName: "KUU1449ProducerScopeIs",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testProduceConsumeEachAndChannelCasts(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.channels.*

            fun main() = runBlocking {
                val p = produce<Int> { send(1); send(2) }
                p.consumeEach { println(it) }
                val p2 = produce<Int> { send(5) }
                val a: Any? = p2
                println(a is Channel<*>)
                println(a is SendChannel<*>)
                println(a is ReceiveChannel<*>)
                (a as Channel<*>).cancel()
                println("done")
            }
            """,
            expectedOutput: "1\n2\ntrue\ntrue\ntrue\ndone\n",
            moduleName: "KUU4366ProduceConsumeEach",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testCallbackFlowAwaitCloseLaunchDoesNotCrash(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.channels.*
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val values = mutableListOf<Int>()
                callbackFlow<Int> {
                    val producer = this
                    launch {
                        trySend(1)
                        delay(10)
                        producer.close()
                    }
                    awaitClose { }
                }.collect { values.add(it) }
                channelFlow<Int> {
                    val producer = this
                    launch {
                        trySend(2)
                        producer.close()
                    }
                    awaitClose { }
                }.collect { values.add(it) }
                println(values)
                println("done")
            }
            """,
            expectedOutput: "[1, 2]\ndone\n",
            moduleName: "KUU1439CallbackFlowScope",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testProduceLaunchInsideBlockDoesNotCrash(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.channels.*

            fun main() = runBlocking {
                val ch = produce<Int> {
                    launch {
                        send(3)
                        close()
                    }.join()
                }
                println(ch.receive())
                println("done")
            }
            """,
            expectedOutput: "3\ndone\n",
            moduleName: "KUU1439ProduceScope",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testProducerFlowFromSuspendStateMachineRunsBlock(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.channels.*
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val values = mutableListOf<Int>()
                channelFlow { send(7); send(9) }.collect { values.add(it) }
                callbackFlow<Int> { trySend(11); close() }.collect { values.add(it) }
                println(values)
            }
            """,
            expectedOutput: "[7, 9, 11]\n",
            moduleName: "SymbolRefProducerEntry",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
