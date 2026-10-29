import kotlin.coroutines.Continuation
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.suspendCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.startCoroutine

// KUU-3719: a suspend function whose suspending calls are all in tail
// position owns no ContinuationImpl on JVM, so suspendCoroutine's
// intercepted() resolves on the caller's interception — the interceptor must
// see exactly one interceptContinuation per logical coroutine. Non-tail and
// multi-suspension callees keep their own machine and still intercept.

private class Counter : ContinuationInterceptor {
    override val key: CoroutineContext.Key<*> = ContinuationInterceptor.Key
    var calls = 0
    override fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T> {
        calls++
        return continuation
    }
}

private suspend fun immediate(): Int = suspendCoroutine { it.resume(42) }
private suspend fun outer(): Int = immediate()
private suspend fun nontail(): Int {
    val x = suspendCoroutine<Int> { it.resume(40) }
    return x + 2
}
private suspend fun twoSuspends(): Int {
    val a = suspendCoroutine<Int> { it.resume(1) }
    val b = suspendCoroutine<Int> { it.resume(2) }
    return a + b
}
private var saved: (() -> Unit)? = null
private suspend fun deferred(): Int = suspendCoroutine { cont ->
    saved = { cont.resume(7) }
}
private suspend fun failer(): Int = suspendCoroutine {
    it.resumeWithException(IllegalStateException("boom"))
}

fun main() {
    var counter = Counter()
    (::immediate).startCoroutine(Continuation<Int>(counter) { println(it.getOrThrow()) })
    println("intercepts:${counter.calls}")

    counter = Counter()
    (::outer).startCoroutine(Continuation<Int>(counter) { println(it.getOrThrow()) })
    println("intercepts:${counter.calls}")

    counter = Counter()
    (::nontail).startCoroutine(Continuation<Int>(counter) { println(it.getOrThrow()) })
    println("intercepts:${counter.calls}")

    counter = Counter()
    (::twoSuspends).startCoroutine(Continuation<Int>(counter) { println(it.getOrThrow()) })
    println("intercepts:${counter.calls}")

    counter = Counter()
    (::deferred).startCoroutine(Continuation<Int>(counter) { println(it.getOrThrow()) })
    println("before:${counter.calls}")
    saved?.invoke()
    println("intercepts:${counter.calls}")

    counter = Counter()
    (::failer).startCoroutine(Continuation<Int>(counter) {
        println(it.exceptionOrNull()?.message ?: "no-ex")
    })
    println("intercepts:${counter.calls}")
}
