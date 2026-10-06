package kotlinx.coroutines

public interface CompletableDeferred<T> : Deferred<T> {
    public fun complete(value: T): Boolean
    public fun completeExceptionally(exception: Throwable): Boolean
}

// KUU-1386: kotlinx's CompletableDeferredImpl is a JobSupport subclass, so
// `cd is JobSupport`/`cd is ChildJob`/`cd is ParentJob` must hold. The bound
// runtime job keeps the same delegation as the removed explicit overrides.
internal class CompletableDeferredImpl<T>(parent: Job?) : JobSupport(true), CompletableDeferred<T> {
    private val job: Job = __kkJobBindWrapper(this, __kkJobNew(), parent)

    init {
        initParentJob(parent)
    }

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
