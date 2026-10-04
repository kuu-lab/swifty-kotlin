import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testProduceNestedLambdaParametersInsideRunBlocking(useArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.channels.*
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val source = flowOf(4, 5, 6)
                val v = "outer"
                val ch = produce {
                    source.collect { v -> send(v) }
                }
                println(ch.receive())
                println(ch.receive())
                println(ch.receive())
                println(v)

                val offset = 10
                val implicit = produce {
                    source.collect { send(it + offset) }
                }
                println(implicit.receive())
                println(implicit.receive())
                println(implicit.receive())
                println("done")
            }
            """,
            expectedOutput: "4\n5\n6\nouter\n14\n15\n16\ndone\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    @Test(arguments: [true, false])
    func testRunBlockingThisSuppliesScopeAcrossSuspensionAndNestedLambdas(useArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.flow.*

            fun <T> Flow<T>.myLaunchIn(scope: CoroutineScope): Job {
                val source = this
                return scope.launch { source.collect { println(it) } }
            }

            fun String.probeScope() = runBlocking {
                val scope: CoroutineScope = this
                println(this@probeScope)
                listOf(9).forEach {
                    flowOf(it).myLaunchIn(this@runBlocking).join()
                }
                flowOf(10).myLaunchIn(scope).join()
            }

            fun main() {
                runBlocking {
                    flowOf(7, 8).myLaunchIn(this).join()
                    delay(1)
                    flowOf(11).myLaunchIn(this).join()
                    println("done")
                }
                "outer".probeScope()
            }
            """,
            expectedOutput: "7\n8\n11\ndone\nouter\n9\n10\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }
}
