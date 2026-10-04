import Testing

extension BundledStdlibExecutionTests {
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
