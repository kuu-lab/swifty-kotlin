import kotlinx.coroutines.*

fun completed(): String {
    val deferred: CompletableDeferred<String> = CompletableDeferred("value")
    val view: Deferred<String> = deferred
    val job: Job = view
    deferred.complete("other")
    view.getCompletionExceptionOrNull()
    job.isCompleted
    return view.getCompleted()
}

suspend fun awaitValue(): Int {
    val deferred = CompletableDeferred<Int>()
    deferred.complete(42)
    return deferred.await()
}

fun completeJob(parent: Job?): Boolean {
    val job: CompletableJob = CompletableJob(parent)
    job.completeExceptionally(IllegalStateException("failure"))
    return job.complete()
}
