import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testLaunchThisIsCoroutineScopeAndSupportsMemberAccess() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            fun main() = runBlocking {
                launch {
                    println(this is CoroutineScope)
                    val s: CoroutineScope? = this as? CoroutineScope
                    println(s != null)
                    println(this.isActive)
                }.join()
            }
            """,
            expectedOutput: "true\ntrue\ntrue\n"
        )
    }

    @Test
    func testCoroutineBuilderThisAcrossSuspensionAndNestedLambdas() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            fun main() = runBlocking {
                println(this is CoroutineScope)
                launch {
                    delay(1)
                    println(this is CoroutineScope)
                    listOf(1).forEach {
                        println(this is CoroutineScope)
                    }
                }.join()
                println(async { this is CoroutineScope }.await())
                coroutineScope {
                    println(this is CoroutineScope)
                }
                supervisorScope {
                    println(this is CoroutineScope)
                }
                withContext(Dispatchers.Default) {
                    println(this is CoroutineScope)
                }
                println("done")
            }
            """,
            expectedOutput: "true\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ndone\n"
        )
    }

    @Test
    func testCoroutineScopeMemberLaunchFromThisDoesNotCrash() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*
            import kotlinx.coroutines.flow.*

            fun <T> Flow<T>.myLaunchIn(scope: CoroutineScope): Job {
                val source = this
                return scope.launch { source.collect { println(it) } }
            }

            fun main() = runBlocking {
                flowOf(7).myLaunchIn(this).join()
            }
            """,
            expectedOutput: "7\n"
        )
    }
}
