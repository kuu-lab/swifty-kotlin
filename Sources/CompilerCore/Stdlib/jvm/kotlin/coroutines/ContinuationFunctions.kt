@file:kotlin.jvm.JvmName("ContinuationKt")
package kotlin.coroutines
import kotlin.jvm.internal.*
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
internal fun <T> startEncoded(block: (Continuation<T>) -> Any?, completion: Continuation<T>) {
    var result: Any? = null
    try { result = block(completion) } catch (failure: Throwable) {
        __jvmResume(completion, kotlin.createFailure(failure))
        return
    }
    if (result !== COROUTINE_SUSPENDED) __jvmResume(completion, result)
}
internal fun <R, T> startEncoded(block: (R, Continuation<T>) -> Any?, receiver: R, completion: Continuation<T>) {
    var result: Any? = null
    try { result = block(receiver, completion) } catch (failure: Throwable) {
        __jvmResume(completion, kotlin.createFailure(failure))
        return
    }
    if (result !== COROUTINE_SUSPENDED) __jvmResume(completion, result)
}

fun <T> (suspend () -> T).startCoroutine(completion: Continuation<T>) {
    val callback = this as (Continuation<T>) -> Any?
    startEncoded(callback, completion)
}
fun <R, T> (suspend R.() -> T).startCoroutine(receiver: R, completion: Continuation<T>) {
    val callback = this as (R, Continuation<T>) -> Any?
    startEncoded(callback, receiver, completion)
}
fun <T> Continuation<T>.resume(value: T) { __jvmResume(this, value) }
fun <T> Continuation<T>.resumeWithException(exception: Throwable) { __jvmResume(this, kotlin.createFailure(exception)) }
suspend fun <T> suspendCoroutine(block: (Continuation<T>) -> Unit): T = __jvmSuspendCoroutine(block)
