package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext
import kotlin.internal.KsSymbolName

public typealias CompletableJob = Job

@KsSymbolName("kk_job_new")
internal external fun __kkJobNew(): Job

@KsSymbolName("kk_supervisor_job_new")
internal external fun __kkSupervisorJobNew(): Job

@KsSymbolName("kk_job_complete")
internal external fun __kkJobComplete(job: Job, value: Any): Boolean

@KsSymbolName("kk_job_cancel_with_cause")
internal external fun __kkJobCancel(job: Job, cause: CancellationException?)

public fun Job(parent: Job? = null): CompletableJob = __kkAttachParent(__kkJobNew(), parent)

public fun SupervisorJob(parent: Job? = null): CompletableJob = __kkAttachParent(__kkSupervisorJobNew(), parent)

internal fun __kkAttachParent(job: Job, parent: Job?): Job {
    if (parent != null) {
        val handle = parent.invokeOnCompletion(onCancelling = true) {
            if (parent.isCancelled) __kkJobCancel(job, parent.getCancellationException())
        }
        job.invokeOnCompletion { handle.dispose() }
    }
    return job
}

public fun Job.complete(): Boolean = __kkJobComplete(this, Unit)

public fun Job.ensureActive() {
    if (!isActive) throw getCancellationException()
}

public val CoroutineContext.isActive: Boolean
    get() = __kkContextIsActive(this)

@KsSymbolName("kk_context_is_active")
internal external fun __kkContextIsActive(context: CoroutineContext): Boolean

public fun CoroutineContext.ensureActive() {
    __kkContextGetJob(this)?.ensureActive()
}

public fun CoroutineContext.cancel(cause: CancellationException? = null) {
    val job = __kkContextGetJob(this)
    if (job != null) __kkJobCancel(job, cause)
}

// KUU-CORO-101: Job/CoroutineContext members that were unresolved wherever
// real-world coroutine code reads its own job (`this.coroutineContext.job`),
// checks why it stopped (`job.getCancellationException()`), or reacts to
// completion (`job.invokeOnCompletion { ... }`). Expressed here in terms of
// `kk_*` runtime bridges, following the same migration pattern as
// Mutex/Semaphore in sync/Sync.kt (KSP-677).

@KsSymbolName("kk_job_get_cancellation_exception")
internal external fun __kkJobGetCancellationException(job: Job): CancellationException

@KsSymbolName("kk_job_invoke_on_completion")
internal external fun __kkJobInvokeOnCompletion(
    job: Job,
    onCancelling: Boolean,
    handler: (Throwable?) -> Unit
): Int

@KsSymbolName("kk_job_dispose_completion_handler")
internal external fun __kkJobDisposeCompletionHandler(job: Job, handlerID: Int)

@KsSymbolName("kk_context_get_job")
internal external fun __kkContextJobHandle(context: CoroutineContext): Long

@KsSymbolName("kk_context_get_job")
internal external fun __kkContextJob(context: CoroutineContext): Job

internal fun __kkContextGetJob(context: CoroutineContext): Job? =
    if (__kkContextJobHandle(context) == 0L) null else __kkContextJob(context)

/// The Job that runs in this context, or throws if the context has none.
public val CoroutineContext.job: Job
    get() = __kkContextGetJob(this) ?: error("Current context doesn't contain Job in it: $this")

public fun Job.getCancellationException(): CancellationException = __kkJobGetCancellationException(this)

public fun Job.invokeOnCompletion(onCancelling: Boolean = false, handler: (cause: Throwable?) -> Unit): DisposableHandle {
    val id = __kkJobInvokeOnCompletion(this, onCancelling, handler)
    return DisposableHandle { __kkJobDisposeCompletionHandler(this, id) }
}
