#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testJobCompletionHandlersPreserveCapturedCells(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*

            fun register(job: Job, handler: (Throwable?) -> Unit) = job.invokeOnCompletion(handler)

            fun main() = runBlocking {
                val job = launch {}
                var calls = 0
                job.invokeOnCompletion { calls++ }
                job.join()
                println(calls)

                val completed = Job()
                var total = 0
                val amount = 2
                val handler: (Throwable?) -> Unit = { total += amount }
                register(completed, handler)
                completed.invokeOnCompletion { total += amount }
                val disposed = completed.invokeOnCompletion { total += 100 }
                disposed.dispose()
                completed.invokeOnCompletion { println(it == null) }
                completed.complete()
                println(total)
                completed.invokeOnCompletion(handler)
                println(total)
                completed.invokeOnCompletion(false, false) { total += 100 }
                println(total)
            }
            """,
            expectedOutput: "1\ntrue\n4\n6\n6\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test
    func testJobCallbacksAndHierarchyResolveAndRun() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*

            fun main() = runBlocking {
                val root = coroutineContext.job
                val job = launch(start = CoroutineStart.LAZY) {}
                println(job.parent === root)
                println(root.children.toList().size)
                var calls = ""
                var capturedCalls = 0
                job.invokeOnCompletion { capturedCalls++ }
                job.invokeOnCompletion { cause -> calls += if (cause == null) "A" else "X" }
                val disposed = job.invokeOnCompletion { calls += "X" }
                job.invokeOnCompletion(true, false) { calls += "B" }
                disposed.dispose()
                job.join()
                println(calls)
                println(capturedCalls)
                println(job.parent == null)
                job.invokeOnCompletion(false, false) { println("unexpected") }.dispose()
                println(job.invokeOnCompletion { println(it == null) }.toString())
                val child = launch(start = CoroutineStart.LAZY) {}
                root.cancelChildren()
                child.join()
                println(child.isCancelled)
                println(root.isActive)
                println(root.children.toList().size)
                val deferred = async(start = CoroutineStart.LAZY) { 42 }
                println(deferred.parent === root)
                deferred.invokeOnCompletion { println(it == null) }
                println(deferred.await())
                println(deferred.parent == null)
            }
            """,
            expectedOutput: "true\n1\nAB\n1\ntrue\ntrue\nNonDisposableHandle\ntrue\ntrue\n0\ntrue\ntrue\n42\ntrue\n"
        )
    }
}
#endif
