import kotlinx.coroutines.*

// KSP-1568: NonCancellable's degenerate Job surface, awaitCancellation, and
// withContext(NonCancellable) — all outputs are deterministic constants.

fun main() = runBlocking {
    // Degenerate always-active Job state.
    println("active=${NonCancellable.isActive}")
    println("completed=${NonCancellable.isCompleted}")
    println("cancelled=${NonCancellable.isCancelled}")
    println("parent=${NonCancellable.parent}")
    println("children=${NonCancellable.children.count()}")
    println("str=${NonCancellable}")

    // cancel() is a no-op on the never-cancellable singleton.
    NonCancellable.cancel()
    println("postCancelActive=${NonCancellable.isActive}")

    // invokeOnCompletion hands back a non-disposable handle; disposing it is
    // a no-op and the handler never runs.
    val handle = NonCancellable.invokeOnCompletion { println("never") }
    handle.dispose()
    println("iocDisposed")

    // The same surface through a Job-typed reference.
    val asJob: Job = NonCancellable
    println("asJobActive=${asJob.isActive}")
    asJob.cancel()
    println("asJobPostCancel=${asJob.isActive}")

    // withContext(NonCancellable) runs its block normally.
    val wc = withContext(NonCancellable) { "wc-result" }
    println("withContext=$wc")

    // awaitCancellation() parks the coroutine until the job is cancelled.
    val parked = launch { awaitCancellation() }
    yield()
    parked.cancelAndJoin()
    println("awaitedThenJoined")
}
