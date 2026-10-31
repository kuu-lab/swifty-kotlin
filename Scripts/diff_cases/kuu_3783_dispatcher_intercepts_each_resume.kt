import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.Continuation
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.startCoroutine
import kotlin.coroutines.suspendCoroutine

// KUU-3783: a source-level ContinuationInterceptor must dispatch every
// resume hop, not just the coroutine's initial start. Interception-
// transparent callees (a suspend call in tail position owns no
// ContinuationImpl of its own on JVM) used to resolve `intercepted()` to
// the raw continuation when the interceptor's product was a custom wrapper,
// so later resumes bypassed the dispatcher entirely.

private class Controller {
    var log = ""
    var resumeIndex = 0
    var callback: (() -> Unit)? = null

    suspend fun <T> suspendWithValue(value: T): T = suspendCoroutine { continuation ->
        log += "suspend($value);"
        callback = {
            continuation.resume(value)
        }
    }

    suspend fun suspendWithException(value: String): Unit = suspendCoroutine { continuation ->
        log += "error($value);"
        callback = {
            continuation.resumeWithException(RuntimeException(value))
        }
    }
}

private abstract class ContinuationDispatcher :
    AbstractCoroutineContextElement(ContinuationInterceptor), ContinuationInterceptor {
    abstract fun <T> dispatchResumeWith(value: Result<T>, continuation: Continuation<T>): Boolean
    override fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T> =
        DispatchedContinuation(this, continuation)
}

private class DispatchedContinuation<T>(
    val dispatcher: ContinuationDispatcher,
    val continuation: Continuation<T>
) : Continuation<T> {
    override val context: CoroutineContext = continuation.context

    override fun resumeWith(value: Result<T>) {
        if (!dispatcher.dispatchResumeWith(value, continuation)) {
            continuation.resumeWith(value)
        }
    }
}

private fun test(c: suspend Controller.() -> Unit): String {
    val controller = Controller()
    c.startCoroutine(
        controller,
        Continuation<Any?>(
            object : ContinuationDispatcher() {
                private fun dispatchResume(block: () -> Unit) {
                    val id = controller.resumeIndex++
                    controller.log += "before $id;"
                    block()
                    controller.log += "after $id;"
                }

                override fun <P> dispatchResumeWith(
                    data: Result<P>,
                    continuation: Continuation<P>
                ): Boolean {
                    dispatchResume {
                        continuation.resumeWith(data)
                    }
                    return true
                }
            }
        ) { it.getOrThrow() }
    )

    while (controller.callback != null) {
        val next = controller.callback!!
        controller.callback = null
        next()
    }
    return controller.log
}

private suspend fun Controller.foo() = suspendWithValue("") + suspendWithValue("O")

private suspend fun Controller.test1() {
    val o = foo()
    val k = suspendWithValue("K")
    log += "$o$k;"
}

private suspend fun Controller.test2() {
    try {
        foo()
        suspendWithException("OK")
        log += "ignore;"
    } catch (e: RuntimeException) {
        log += "${e.message};"
    }
}

fun main() {
    var result = test { test1() }
    println(result)
    result = test { test2() }
    println(result)
}
