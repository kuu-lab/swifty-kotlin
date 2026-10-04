#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testCompletableJobWrapperLifecycle() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*

            fun main() = runBlocking {
                val completable = CompletableJob()
                val job: Job = completable
                var completions = 0
                job.invokeOnCompletion { cause ->
                    println(cause == null)
                    completions++
                }
                println(job.isActive)
                println(completable.complete())
                println(completable.complete())
                job.join()
                println(job.isCompleted)
                println(completions)

                val cancelled = CompletableJob()
                cancelled.cancel()
                println(cancelled.isCancelled)
                println(cancelled.isCompleted)
                println(cancelled.complete())
                println(cancelled.getCancellationException() is CancellationException)

                val parent = CompletableJob()
                val child = CompletableJob(parent)
                parent.cancel()
                println(child.isCancelled)
                println(child.isCompleted)

                val failed = CompletableJob()
                failed.invokeOnCompletion { cause -> println(cause?.message) }
                println(failed.completeExceptionally(IllegalStateException("failure")))
                println(failed.complete())
                println(failed.isCancelled)
                println("done")
            }
            """,
            expectedOutput: "true\ntrue\ntrue\nfalse\ntrue\n1\ntrue\ntrue\nfalse\ntrue\ntrue\ntrue\nfailure\ntrue\nfalse\ntrue\ndone\n"
        )
    }

    @Test
    func testCompletableDeferredSourceAwait() throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.*

            suspend fun read(deferred: Deferred<String>): String = deferred.await()

            fun main() = runBlocking {
                val deferred = CompletableDeferred<String>()
                launch { deferred.complete("completed") }
                println(read(deferred))
                println(deferred.getCompleted())
                println(deferred.getCompletionExceptionOrNull() == null)
                println("done")
            }
            """,
            expectedOutput: "completed\ncompleted\ntrue\ndone\n",
            allowDefaultStdlibLibrary: false
        )
    }
}
#endif
