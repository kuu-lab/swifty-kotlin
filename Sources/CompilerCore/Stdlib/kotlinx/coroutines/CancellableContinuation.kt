package kotlinx.coroutines

import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn
import kotlin.internal.KsSymbolName

public interface CancellableContinuation<in T> : Continuation<T> {
    public val isActive: Boolean
    public val isCompleted: Boolean
    public val isCancelled: Boolean
    public fun cancel(cause: Throwable? = null): Boolean
    public fun invokeOnCancellation(handler: (cause: Throwable?) -> Unit)
    public fun resume(value: T, onCancellation: ((cause: Throwable) -> Unit)? = null)
    public fun <R : T> resume(value: R, onCancellation: (cause: Throwable, value: R, context: CoroutineContext) -> Unit)
    @InternalCoroutinesApi
    public fun tryResume(value: T, idempotent: Any? = null): Any?
    @InternalCoroutinesApi
    public fun tryResumeWithException(exception: Throwable): Any?
    @InternalCoroutinesApi
    public fun completeResume(token: Any)
}

@KsSymbolName("__kk_cancellable_continuation_new")
internal external fun <T> cancellableContinuationNew(delegate: Continuation<T>): Any

@KsSymbolName("__kk_cancellable_continuation_state")
internal external fun cancellableContinuationState(handle: Any): Int

@KsSymbolName("__kk_cancellable_continuation_resume")
internal external fun <T> cancellableContinuationResume(handle: Any, result: Result<T>, onCancellation: Any)

@KsSymbolName("__kk_cancellable_continuation_cancel")
internal external fun cancellableContinuationCancel(handle: Any, cause: Throwable?): Boolean

@KsSymbolName("__kk_cancellable_continuation_invoke_on_cancellation")
internal external fun cancellableContinuationInvokeOnCancellation(handle: Any, handler: Any)

@KsSymbolName("__kk_cancellable_continuation_try_resume")
internal external fun <T> cancellableContinuationTryResume(handle: Any, result: Result<T>, idempotent: Any?): Any?

@KsSymbolName("__kk_cancellable_continuation_complete_resume")
internal external fun cancellableContinuationCompleteResume(handle: Any, token: Any)

@KsSymbolName("__kk_cancellable_continuation_get_result")
internal external fun cancellableContinuationGetResult(handle: Any): Any?

@PublishedApi
internal class CancellableContinuationImpl<T>(private val delegate: Continuation<T>) : CancellableContinuation<T> {
    private val handle = cancellableContinuationNew(delegate)

    override val context: CoroutineContext
        get() = delegate.context
    override val isActive: Boolean
        get() = cancellableContinuationState(handle) == 0
    override val isCompleted: Boolean
        get() = cancellableContinuationState(handle) != 0
    override val isCancelled: Boolean
        get() = cancellableContinuationState(handle) == 2

    override fun resumeWith(result: Result<T>) {
        val callback: (Throwable) -> Unit = { }
        cancellableContinuationResume(handle, result, callback)
    }

    override fun resume(value: T, onCancellation: ((Throwable) -> Unit)?) {
        val callback: (Throwable) -> Unit = { cause ->
            if (onCancellation != null) onCancellation(cause)
        }
        cancellableContinuationResume(handle, Result.success(value), callback)
    }

    override fun <R : T> resume(value: R, onCancellation: (Throwable, R, CoroutineContext) -> Unit) {
        val callback: (Throwable) -> Unit = { cause ->
            onCancellation(cause, value, context)
        }
        cancellableContinuationResume(handle, Result.success(value), callback)
    }

    override fun cancel(cause: Throwable?): Boolean = cancellableContinuationCancel(handle, cause)

    override fun invokeOnCancellation(handler: (Throwable?) -> Unit) {
        cancellableContinuationInvokeOnCancellation(handle, handler)
    }

    override fun tryResume(value: T, idempotent: Any?): Any? =
        cancellableContinuationTryResume(handle, Result.success(value), idempotent)

    override fun tryResumeWithException(exception: Throwable): Any? =
        cancellableContinuationTryResume(handle, Result.failure<T>(exception), null)

    override fun completeResume(token: Any) {
        cancellableContinuationCompleteResume(handle, token)
    }

    @PublishedApi
    internal fun getResult(): Any? = cancellableContinuationGetResult(handle)
}

public suspend inline fun <T> suspendCancellableCoroutine(crossinline block: (CancellableContinuation<T>) -> Unit): T =
    suspendCoroutineUninterceptedOrReturn<T> { delegate ->
        val continuation = CancellableContinuationImpl<T>(delegate)
        block(continuation)
        continuation.getResult()
    }
