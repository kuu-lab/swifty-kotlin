package kotlinx.coroutines

import kotlin.coroutines.Continuation

public abstract class DispatchedTask<in T>(public var resumeMode: Int) {
    public abstract val delegate: Continuation<@UnsafeVariance T>
    public abstract fun takeState(): Any?
    public open fun cancelCompletedResult(takenState: Any?, cause: Throwable) {}
    public open fun getExceptionalResult(state: Any?): Throwable? = state as? Throwable
    public open fun <R> getSuccessfulResult(state: Any?): R = state as R
}
