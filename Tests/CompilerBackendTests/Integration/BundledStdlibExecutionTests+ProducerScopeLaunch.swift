import Testing

// KUU-1439: `callbackFlow`/`channelFlow`/`produce` hand the producer block the
// raw channel handle as its `ProducerScope` receiver, so `CoroutineScope`
// member calls on `this` (launch/async/cancel) reach the
// `kk_coroutine_scope_*` bridges carrying a channel handle and used to panic
// with `KSWIFTK-RUNTIME-0001 launch received an invalid scope`. These tests
// pin the fixed behaviour end-to-end: the scope bridges resolve the channel
// back to the CoroutineScope facet the producer launcher bound to it.
extension BundledStdlibExecutionTests {
    /// Minimal reproduction from the issue: `launch` inside `callbackFlow`'s
    /// producer block plus `awaitClose` used to crash before the block ran.
    /// `channelFlow` shares the same launcher, so it is pinned alongside.
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

    /// `produce`/`actor` reach the runtime through `__kk_produce_launch`, a
    /// separate launcher from the flow builders; its channel-backed
    /// ProducerScope must resolve for CoroutineScope member calls too.
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
}
