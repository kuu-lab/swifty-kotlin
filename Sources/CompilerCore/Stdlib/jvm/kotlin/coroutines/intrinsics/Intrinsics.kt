package kotlin.coroutines.intrinsics

import kotlin.coroutines.Continuation
import kotlin.coroutines.jvm.internal.BaseContinuationImpl
import kotlin.coroutines.jvm.internal.ContinuationImpl

private object CoroutineSuspended
val COROUTINE_SUSPENDED: Any get() = CoroutineSuspended

@Suppress("UNCHECKED_CAST")
public fun <T> Continuation<T>.intercepted(): Continuation<T> {
    if (this is ContinuationImpl) return intercepted() as Continuation<T>
    return this
}

@Suppress("UNCHECKED_CAST")
public fun <T> (suspend () -> T).createCoroutineUnintercepted(completion: Continuation<T>): Continuation<Unit> {
    val callable: Any = this
    if (callable is BaseContinuationImpl) return callable.create(completion)
    val function = this as (Continuation<T>) -> Any?
    return CreatedContinuation(completion, function) as Continuation<Unit>
}

@Suppress("UNCHECKED_CAST")
public fun <R, T> (suspend R.() -> T).createCoroutineUnintercepted(receiver: R, completion: Continuation<T>): Continuation<Unit> {
    val callable: Any = this
    if (callable is BaseContinuationImpl) return callable.create(receiver, completion)
    val function = this as (R, Continuation<T>) -> Any?
    return CreatedContinuation<T>(completion) { function(receiver, it) } as Continuation<Unit>
}

@Suppress("UNCHECKED_CAST")
private class CreatedContinuation<T>(completion: Continuation<T>, private val block: (Continuation<T>) -> Any?) :
    ContinuationImpl(completion as Continuation<Any?>) {
    private var state = 0

    override fun invokeSuspend(result: Any?): Any? {
        if (state == 0) {
            state = 2
            kotlin.throwOnFailure(result)
            state = 1
            try {
                val outcome = block(this as Continuation<T>)
                if (outcome !== COROUTINE_SUSPENDED) state = 2
                return outcome
            } catch (failure: Throwable) {
                state = 2
                throw failure
            }
        }
        if (state == 1) {
            state = 2
            kotlin.throwOnFailure(result)
            return result
        }
        throw IllegalStateException("This coroutine had already completed")
    }
}
