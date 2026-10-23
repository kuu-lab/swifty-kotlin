#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testCompletableFutureCoroutineInterop() throws {
        try compileAndRunKotlin(
            """
            import java.util.concurrent.CompletableFuture
            import kotlinx.coroutines.*
            import kotlinx.coroutines.future.*

            fun main() = runBlocking {
                var observed = "none"
                val chained = CompletableFuture.completedFuture(5)
                    .thenApply { it * 2 }
                    .thenCompose { CompletableFuture.completedFuture("value=$it") }
                    .whenComplete { value, failure -> observed = "$value:${failure == null}" }
                println(chained.await())
                println(observed)

                val pending = CompletableFuture<Int>()
                val pendingCompleter = future { pending.complete(41); Unit }
                println(pending.await())
                pendingCompleter.await()

                val all = CompletableFuture.allOf(
                    CompletableFuture.completedFuture(1),
                    CompletableFuture.completedFuture(2)
                )
                all.await()
                println(all.isDone())
                println(CompletableFuture.anyOf(CompletableFuture.completedFuture("first")).await())

                val deferred = CompletableDeferred<Int>()
                val deferredFuture = deferred.asCompletableFuture()
                val deferredCompleter = future { deferred.complete(7); Unit }
                println(deferredFuture.await())
                deferredCompleter.await()
                println(deferredFuture.get())
                println(CompletableFuture.completedFuture(9).asDeferred().await())

                val failedStage = CompletableFuture.failedFuture<Int>(IllegalStateException("stage-boom"))
                try {
                    failedStage.asDeferred().await()
                } catch (failure: IllegalStateException) {
                    println(failure.message)
                }
                val cancelledStage = CompletableFuture<Int>()
                cancelledStage.cancel(false)
                println(cancelledStage.asDeferred().isCancelled)

                val failedDeferred = CompletableDeferred<Int>()
                val failedFuture = failedDeferred.asCompletableFuture()
                val failureCompleter = future {
                    failedDeferred.completeExceptionally(IllegalStateException("boom")); Unit
                }
                try {
                    failedFuture.await()
                } catch (failure: IllegalStateException) {
                    println(failure.message)
                }
                failureCompleter.await()

                val cancelledDeferred = CompletableDeferred<Int>()
                val cancelledFuture = cancelledDeferred.asCompletableFuture()
                cancelledDeferred.cancel()
                println(cancelledFuture.isCancelled())

                val job = CompletableJob()
                val jobFuture = job.asCompletableFuture()
                val jobCompleter = future { job.complete(); Unit }
                jobFuture.await()
                jobCompleter.await()
                println(jobFuture.isDone())

                val failedJob = CompletableJob()
                failedJob.completeExceptionally(IllegalStateException("job-boom"))
                try {
                    failedJob.asCompletableFuture().await()
                } catch (failure: IllegalStateException) {
                    println(failure.message)
                }
                val cancelledJob = CompletableJob()
                val cancelledJobFuture = cancelledJob.asCompletableFuture()
                cancelledJob.cancel()
                println(cancelledJobFuture.isCancelled())

                println(future { 20 + 22 }.await())
                println("done")
            }
            """,
            expectedOutput: "value=10\nvalue=10:true\n41\ntrue\nfirst\n7\n7\n9\nstage-boom\ntrue\nboom\ntrue\ntrue\njob-boom\ntrue\n42\ndone\n"
        )
    }
}
#endif
