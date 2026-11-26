import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testCallbackFlowProducerIsActive(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.channels.*
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                callbackFlow<Int> {
                    println(isActive)
                    println(coroutineContext[Job]?.isActive)
                    val producer = this
                    launch { producer.close() }
                    awaitClose { }
                }.collect { }
                println("done")
            }
            """,
            expectedOutput: "true\ntrue\ndone\n",
            moduleName: "KUU1450CallbackFlowIsActive",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testChannelFlowAndProduceProducerIsActive(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.channels.*
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                channelFlow<Int> {
                    println(isActive)
                    println(coroutineContext[Job]?.isActive)
                    send(1)
                    close()
                }.collect { println(it) }
                val produced = produce<Int> {
                    println(isActive)
                    println(coroutineContext[Job]?.isActive)
                    send(2)
                    close()
                }
                for (value in produced) { println(value) }
                println("done")
            }
            """,
            expectedOutput: "true\ntrue\n1\ntrue\ntrue\n2\ndone\n",
            moduleName: "KUU1450ChannelFlowIsActive",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
