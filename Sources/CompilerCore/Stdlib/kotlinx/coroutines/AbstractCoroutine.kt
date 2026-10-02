package kotlinx.coroutines

import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext

public abstract class AbstractCoroutine<in T>(
    parentContext: CoroutineContext,
    initParentJob: Boolean,
    active: Boolean
) : JobSupport(active), Continuation<T>, CoroutineScope {
    public final override val context: CoroutineContext = parentContext
    public override val coroutineContext: CoroutineContext get() = context

    init {
        if (initParentJob) initParentJob(__kkContextGetJob(parentContext))
    }

    protected open fun onCompleted(value: T) {}
    protected open fun onCancelled(cause: Throwable, handled: Boolean) {}
    protected open fun afterResume(state: Any?) {
        afterCompletion(state)
    }

    public final override fun resumeWith(result: Result<T>) {
        val failure = result.exceptionOrNull()
        if (failure != null) {
            completeExceptionally(failure)
            onCancelled(failure, false)
        } else {
            val value = result.getOrThrow()
            complete(value as Any)
            onCompleted(value)
        }
        afterResume(result)
    }
}
