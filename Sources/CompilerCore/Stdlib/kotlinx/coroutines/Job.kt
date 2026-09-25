package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext
import kotlin.internal.KsSymbolName

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
internal external fun __kkContextGetJob(context: CoroutineContext): Job?

/// The Job that runs in this context, or throws if the context has none.
public val CoroutineContext.job: Job
    get() = __kkContextGetJob(this) ?: error("Current context doesn't contain Job in it: $this")

public fun Job.getCancellationException(): CancellationException = __kkJobGetCancellationException(this)

public fun Job.invokeOnCompletion(onCancelling: Boolean = false, handler: (cause: Throwable?) -> Unit): DisposableHandle {
    val id = __kkJobInvokeOnCompletion(this, onCancelling, handler)
    return DisposableHandle { __kkJobDisposeCompletionHandler(this, id) }
}
