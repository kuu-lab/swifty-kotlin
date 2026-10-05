import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testNativeDispatcherGetUsesSourceDefault(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.coroutines.*
            import kotlinx.coroutines.*
            object MissingKey : CoroutineContext.Key<CoroutineContext.Element>
            @OptIn(ExperimentalStdlibApi::class)
            object DispatcherKey : AbstractCoroutineContextKey<ContinuationInterceptor, ContinuationInterceptor>(
                ContinuationInterceptor.Key, { element: CoroutineContext.Element -> if (element === Dispatchers.Default) Dispatchers.Default else null }
            )
            class CustomInterceptor : ContinuationInterceptor {
                override val key: CoroutineContext.Key<*> get() = ContinuationInterceptor.Key
                override fun <T> interceptContinuation(c: Continuation<T>): Continuation<T> = c
                override fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? {
                    println("override")
                    return null
                }
            }
            class CustomDispatcher : CoroutineDispatcher() {
                override fun <T> interceptContinuation(c: Continuation<T>): Continuation<T> = c
                override fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? {
                    println("dispatcher override")
                    return null
                }
            }
            @OptIn(ExperimentalStdlibApi::class)
            fun main() {
                println(Dispatchers.Default[MissingKey] == null)
                println(Dispatchers.Main[MissingKey] == null)
                val interceptor: ContinuationInterceptor = Dispatchers.Default
                println(interceptor[ContinuationInterceptor.Key] === interceptor)
                println(Dispatchers.Default[DispatcherKey] === Dispatchers.Default)
                println(interceptor.minusKey(DispatcherKey) === EmptyCoroutineContext)
                val custom: ContinuationInterceptor = CustomInterceptor()
                println(custom[MissingKey] == null)
                val customDispatcher: CoroutineDispatcher = CustomDispatcher()
                println(customDispatcher[MissingKey] == null)
            }
            """,
            expectedOutput: "true\ntrue\ntrue\ntrue\ntrue\noverride\ntrue\ndispatcher override\ntrue\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [false, true])
    func testScopeBuilderReceiverFunctionValues(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*

            suspend fun throughCoroutine(block: suspend CoroutineScope.() -> Int): Any =
                coroutineScope(block = block)
            suspend fun throughSupervisor(block: suspend CoroutineScope.() -> Int): Any =
                supervisorScope(block)

            fun main() = runBlocking {
                val block: suspend CoroutineScope.() -> Int = { 23 }
                println(coroutineScope(block = block))
                println(supervisorScope(block = block))
                val nullable: suspend CoroutineScope.() -> Int? = { null }
                println(coroutineScope(block = nullable))
                println(supervisorScope(block = nullable))
                val label = "captured"
                val increment = 4
                val offset = 19
                var state = 3
                val captured: suspend CoroutineScope.() -> Int = {
                    delay(1)
                    println(label)
                    this.ensureActive()
                    println(this.coroutineContext.job === currentCoroutineContext().job)
                    state += increment
                    state + offset
                }
                println(throughCoroutine(captured))
                println(throughSupervisor(captured))
                println(state)
                println(coroutineScope {
                    val scope: CoroutineScope = this
                    scope.async { delay(1); 7 }.await()
                })
                println(supervisorScope {
                    val scope: CoroutineScope = this
                    scope.async { delay(1); 11 }.await()
                })
                val throwing: suspend CoroutineScope.() -> Int = {
                    delay(1)
                    throw IllegalArgumentException(label)
                }
                try {
                    throughCoroutine(throwing)
                } catch (e: IllegalArgumentException) {
                    println(e.message)
                }
                try {
                    throughSupervisor(throwing)
                } catch (e: IllegalArgumentException) {
                    println(e.message)
                }
                Unit
            }
            """,
            expectedOutput: "23\n23\nnull\nnull\ncaptured\ntrue\n26\ncaptured\ntrue\n30\n11\n7\n11\ncaptured\ncaptured\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [false, true])
    func testTestSchedulerLongClockABI(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.ExperimentalCoroutinesApi
            import kotlinx.coroutines.test.TestScope
            import kotlinx.coroutines.test.advanceTimeBy
            import kotlinx.coroutines.test.currentTime

            @OptIn(ExperimentalCoroutinesApi::class)
            fun main() {
                val scope = TestScope()
                println(scope.currentTime)
                scope.testScheduler.advanceTimeBy(4294967296L)
                println(scope.testScheduler.currentTime)
                println(scope.currentTime)
            }
            """,
            expectedOutput: "0\n4294967296\n4294967296\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [false, true])
    func testMainDispatcherNominalAndImmediate(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.coroutines.*
            import kotlinx.coroutines.*

            class CustomDispatcher : MainCoroutineDispatcher() {
                override val immediate: MainCoroutineDispatcher
                    get() { println("custom immediate"); return this }
                override fun <T> interceptContinuation(c: Continuation<T>): Continuation<T> = c
            }
            class ThrowingDispatcher : MainCoroutineDispatcher() {
                override val immediate: MainCoroutineDispatcher
                    get() = throw IllegalArgumentException("getter failure")
                override fun <T> interceptContinuation(c: Continuation<T>): Continuation<T> = c
            }
            fun main() {
                val main: MainCoroutineDispatcher = Dispatchers.Main
                println(main.immediate === main)
                println(main.limitedParallelism(1) === main)
                try { main.limitedParallelism(0) } catch (e: IllegalArgumentException) { println("invalid parallelism") }
                val custom: MainCoroutineDispatcher = CustomDispatcher()
                println(custom.immediate === custom)
                val throwing: MainCoroutineDispatcher = ThrowingDispatcher()
                try { throwing.immediate } catch (e: IllegalArgumentException) { println("caught getter") }
            }
            """,
            expectedOutput: "true\ntrue\ninvalid parallelism\ncustom immediate\ntrue\ncaught getter\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [false, true])
    func testCoroutineScopeAmbientContext(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*

            class ContextOwner(val coroutineContext: String) {
                fun value(): String = coroutineContext
            }

            fun main() = runBlocking {
                println(ContextOwner("custom").value())
                println(coroutineContext.job.isActive)
                supervisorScope {
                    println(coroutineContext.isActive)
                }
                launch {
                    println(coroutineContext.job.isActive)
                }.join()
            }
            """,
            expectedOutput: "custom\ntrue\ntrue\ntrue\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [false, true])
    func testCoroutineNominalsPreserveJobBridges(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*

            fun main() = runBlocking {
                val job: CompletableJob = Job()
                println(job.isActive)
                println(job.complete())
                job.awaitCompletion()
                println(job.isCompleted)
                println(job.complete())
                val failed: CompletableJob = Job()
                println(failed.completeExceptionally(Exception("failed")))
                println(failed.isCancelled)
                val supervisor: CompletableJob = SupervisorJob()
                supervisor.cancel()
                println(supervisor.isCancelled)
                val deferred = async { 42 }
                println(deferred.await())
                val child: Job = deferred
                child.join()
                println(child.isCompleted)
                val local = JobImpl()
                println(local.isActive)
                println(local.complete())
                println(local.isCompleted)
                val handle: ChildHandle = NonDisposableHandle
                println(handle.parent == null)
                println(handle.childCancelled(Exception("child")))
                handle.dispose()
            }
            """,
            expectedOutput: "true\ntrue\ntrue\nfalse\ntrue\ntrue\ntrue\n42\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
