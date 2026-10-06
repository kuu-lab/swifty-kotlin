import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testJobAndDispatcherElementKeys(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.coroutines.*
            import kotlinx.coroutines.*

            object CustomKey : CoroutineContext.Key<CustomElement>
            class CustomElement : CoroutineContext.Element {
                override val key: CoroutineContext.Key<*> get() = CustomKey
            }
            class CustomDispatcher : CoroutineDispatcher() {
                override val key: CoroutineContext.Key<*> get() = CustomKey
                override fun <T> interceptContinuation(c: Continuation<T>): Continuation<T> = c
            }
            class DefaultDispatcher : CoroutineDispatcher() {
                override fun <T> interceptContinuation(c: Continuation<T>): Continuation<T> = c
            }
            class SuperDispatcher : CoroutineDispatcher() {
                override val key: CoroutineContext.Key<*> get() = super.key
                override fun <T> interceptContinuation(c: Continuation<T>): Continuation<T> = c
            }
            class DelegatingJob : Job by Job() {
                override val key: CoroutineContext.Key<*> get() = super<Job>.key
            }

            fun keyOf(element: CoroutineContext.Element) = element.key

            fun main() = runBlocking {
                val job = Job()
                println(job.key === Job.Key)
                println(keyOf(job) === Job.Key)
                val child = launch {}
                println(child.key === Job.Key)
                println(keyOf(child) === Job.Key)
                child.invokeOnCompletion { println("cb") }
                child.join()
                println("after")
                println(Dispatchers.Default.key === ContinuationInterceptor.Key)
                println(keyOf(Dispatchers.Default) === ContinuationInterceptor.Key)
                val name = CoroutineName("n")
                println(name.key === CoroutineName.Key)
                println(keyOf(name) === CoroutineName.Key)
                println(keyOf(CustomElement()) === CustomKey)
                val custom: CoroutineDispatcher = CustomDispatcher()
                println(custom.key === CustomKey)
                println(keyOf(custom) === CustomKey)
                val defaultDispatcher: CoroutineDispatcher = DefaultDispatcher()
                println(defaultDispatcher.key === ContinuationInterceptor.Key)
                println(keyOf(defaultDispatcher) === ContinuationInterceptor.Key)
                println(keyOf(SuperDispatcher()) === ContinuationInterceptor.Key)
                println(keyOf(DelegatingJob()) === Job.Key)
                val nullable: Job? = child
                println(nullable?.key === Job.Key)
                val task = async { 7 }
                println(task.key === Job.Key)
                println(keyOf(task) === Job.Key)
                task.await()
                val completed = CompletableDeferred<Int>(7)
                println(completed.key === Job.Key)
                println(keyOf(completed) === Job.Key)
            }
            """,
            expectedOutput: "true\ntrue\ntrue\ntrue\ncb\nafter\n" + String(repeating: "true\n", count: 16),
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
