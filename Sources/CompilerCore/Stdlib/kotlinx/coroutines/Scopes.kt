package kotlinx.coroutines

import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext

public open class ScopedCoroutine<T>(
    context: CoroutineContext,
    public val uCont: Continuation<T>
) : AbstractCoroutine<T>(context, true, true) {
    protected override fun onCompleted(value: T) {
        uCont.resumeWith(Result.success(value))
    }

    protected override fun onCancelled(cause: Throwable, handled: Boolean) {
        uCont.resumeWith(Result.failure<T>(cause))
    }
}
