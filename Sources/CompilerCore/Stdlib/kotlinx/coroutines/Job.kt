package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext
import kotlin.internal.KsSymbolName
import kotlin.sequences.asSequence

public interface Job : CoroutineContext.Element {
    public companion object Key : CoroutineContext.Key<Job>

    public override val key: CoroutineContext.Key<*> get() = Key

    @KsSymbolName("kk_job_is_active")
    public val isActive: Boolean

    @KsSymbolName("kk_job_is_completed")
    public val isCompleted: Boolean

    @KsSymbolName("kk_job_is_cancelled")
    public val isCancelled: Boolean

    @KsSymbolName("kk_job_cancel")
    public fun cancel()

    @KsSymbolName("kk_job_cancel_with_cause")
    public fun cancel(cause: Any?)

    @KsSymbolName("kk_job_join")
    public suspend fun join()

    @KsSymbolName("kk_job_await_completion")
    public suspend fun awaitCompletion()

    @KsSymbolName("kk_job_complete")
    public fun complete(value: Any): Boolean

    @KsSymbolName("kk_job_complete_exceptionally")
    public fun completeExceptionally(exception: Any?): Boolean
}

public interface ChildJob : Job {
    public fun parentCancelled(parentJob: ParentJob)
}

public interface ParentJob : Job {
    public fun getChildJobCancellationCause(): CancellationException
}

public interface ChildHandle : DisposableHandle {
    public val parent: Job?
    public fun childCancelled(cause: Throwable): Boolean
}

// KUU-CORO-101: Job/CoroutineContext members that were unresolved wherever
// real-world coroutine code reads its own job (`this.coroutineContext.job`),
// checks why it stopped (`job.getCancellationException()`), or reacts to
// completion (`job.invokeOnCompletion { ... }`). Expressed here in terms of
// `kk_*` runtime bridges, following the same migration pattern as
// Mutex/Semaphore in sync/Sync.kt (KSP-677).

@KsSymbolName("kk_job_get_cancellation_exception")
internal external fun __kkJobGetCancellationException(job: Job): CancellationException

@KsSymbolName("__kk_job_invoke_on_completion")
internal external fun __kkJobInvokeOnCompletion(
    job: Job,
    onCancelling: Boolean,
    invokeImmediately: Boolean,
    handler: (Throwable?) -> Unit
): Int

@KsSymbolName("__kk_job_dispose_handle")
internal external fun __kkJobDisposeCompletionHandler(job: Job, handlerID: Int)

@KsSymbolName("__kk_job_children")
internal external fun __kkJobChildren(job: Job): List<Job>

@KsSymbolName("__kk_job_parent")
internal external fun __kkJobParent(job: Job): Job?

@KsSymbolName("kk_context_get_job")
internal external fun __kkContextGetJob(context: CoroutineContext): Job?

/// The Job that runs in this context, or throws if the context has none.
public val CoroutineContext.job: Job
    get() = __kkContextGetJob(this) ?: error("Current context doesn't contain Job in it: $this")

public fun Job.getCancellationException(): CancellationException = __kkJobGetCancellationException(this)

public val Job.children: Sequence<Job>
    get() = __kkJobChildren(this).asSequence()

public val Job.parent: Job?
    get() = __kkJobParent(this)

public fun Job.cancelChildren(cause: CancellationException? = null) {
    for (child in children) {
        child.cancel(cause)
    }
}

public fun Job.invokeOnCompletion(handler: (cause: Throwable?) -> Unit): DisposableHandle =
    invokeOnCompletion(false, true, handler)

public fun Job.invokeOnCompletion(
    onCancelling: Boolean,
    invokeImmediately: Boolean = true,
    handler: (cause: Throwable?) -> Unit
): DisposableHandle {
    val id = __kkJobInvokeOnCompletion(this, onCancelling, invokeImmediately, handler)
    if (id == 0) return NonDisposableHandle
    return DisposableHandle { __kkJobDisposeCompletionHandler(this, id) }
}

// `Job.cancelAndJoin` / `Job.cancelAndJoin(cause)` from kotlinx-coroutines
// Job.kt: cancel first so `join()` waits for the job to actually finish
// winding down instead of suspending on a still-running job.
public suspend fun Job.cancelAndJoin() {
    cancel()
    join()
}

public suspend fun Job.cancelAndJoin(cause: CancellationException?) {
    cancel(cause)
    join()
}
