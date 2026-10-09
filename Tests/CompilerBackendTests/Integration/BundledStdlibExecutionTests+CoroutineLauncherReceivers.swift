import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testProduceRetainsCapturedFlow(useArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.channels.*
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val source = flowOf(4)
                val channel = produce<Int> { source.collect { send(it) } }
                println(channel.receive())
            }
            """,
            expectedOutput: "4\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowSuspendCollectorFailureReachesCatchOutsideRunBlockingHelper(useArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.flow.*
            import kotlinx.coroutines.runBlocking

            fun runCollect(source: Flow<Int>, action: suspend (Int) -> Unit) = runBlocking {
                source.collect(action)
            }

            fun main() {
                val failure: suspend (Int) -> Unit = { throw IllegalArgumentException("converted") }
                try { runCollect(flowOf(1), failure) }
                catch (e: IllegalArgumentException) { println("specific:${e.message}") }
                catch (e: Throwable) { println("other:${e.message}") }
            }
            """,
            expectedOutput: "specific:converted\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    @Test(arguments: [true, false])
    func testProduceNestedLambdaParametersInsideRunBlocking(useArtifact: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("coroutine_produce_nested_lambda.kt", file: #filePath),
            expectedOutput: "4\n5\n6\nouter\n14\n15\n16\ndone\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    @Test(arguments: [true, false])
    func testRunBlockingThisSuppliesScopeAcrossSuspensionAndNestedLambdas(useArtifact: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("coroutine_run_blocking_this.kt", file: #filePath),
            expectedOutput: "7\n8\n11\ndone\nouter\n9\n10\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }
}
