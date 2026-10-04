package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext

public interface CompletableDeferred<T> : Deferred<T> {
    public fun complete(value: T): Boolean
    public fun completeExceptionally(exception: Throwable): Boolean
}

internal class CompletableDeferredImpl<T>(parent: Job?) : CompletableDeferred<T> {
    private val job: Job = __kkJobBindWrapper(this, __kkJobNew(), parent)

    override val isActive: Boolean get() = job.isActive
    override val isCompleted: Boolean get() = job.isCompleted
    override val isCancelled: Boolean get() = job.isCancelled

    override val key: CoroutineContext.Key<*>
        get() = CompletableJobKey

    override fun complete(value: T): Boolean = __kkJobComplete(job, value)

    override fun completeExceptionally(exception: Throwable): Boolean =
        __kkJobCompleteExceptionally(job, exception)

    override suspend fun await(): T {
        __kkJobJoin(job)
        return getCompleted()
    }
}

public fun <T> CompletableDeferred(parent: Job? = null): CompletableDeferred<T> =
    CompletableDeferredImpl<T>(parent)

public fun <T> CompletableDeferred(value: T): CompletableDeferred<T> {
    val deferred = CompletableDeferredImpl<T>(null)
    deferred.complete(value)
    return deferred
}
