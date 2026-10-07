import Testing

// KUU-1450: `channelFlow`/`callbackFlow` launch their producer through
// `runtimeKxMiniProduceWithCont`, which used to run the body without calling
// `markStarted()` on the producer job — the job stayed `.new`, so
// `CoroutineScope.isActive`/`coroutineContext[Job]?.isActive` inside the
// running producer answered false (JVM: true). The sibling
// `__kk_produce_launch*` launchers behind `produce`/`actor` already mark the
// job started; these tests pin `isActive == true` across all three builders.
extension BundledStdlibExecutionTests {
    /// Minimal reproduction from the issue: `isActive` and
    /// `coroutineContext[Job]?.isActive` inside a `callbackFlow` producer.
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

    /// `channelFlow` shares the same launcher, and `produce` reaches the
    /// runtime through `__kk_produce_launch` — the producer job must read
    /// `.active` in every builder shape.
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
