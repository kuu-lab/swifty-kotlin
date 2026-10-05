import kotlin.coroutines.Continuation
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.intrinsics.createCoroutineUnintercepted
import kotlin.coroutines.intrinsics.intercepted

private class RecordingInterceptor : ContinuationInterceptor {
    override val key: CoroutineContext.Key<*> = ContinuationInterceptor.Key
    var calls = 0
    override fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T> {
        calls++
        return continuation
    }
}

private class Probe(override val context: CoroutineContext) : Continuation<String> {
    override fun resumeWith(result: Result<String>) {
        println(result.getOrThrow())
    }
}

private class ThrowingContext : Continuation<Int> {
    override val context: CoroutineContext
        get() = throw IllegalStateException("context must not be read")
    override fun resumeWith(result: Result<Int>) {}
}

private suspend fun value(): Int = 42

private fun <T> generic(continuation: Continuation<T>): Continuation<T> = continuation.intercepted()

fun main() {
    val interceptor = RecordingInterceptor()
    val ordinary: Continuation<String> = Probe(interceptor)
    println(generic(ordinary) === ordinary)
    println(ordinary.intercepted().intercepted() === ordinary)
    ordinary.intercepted().resume("ok")
    println(interceptor.calls)
    val throwing: Continuation<Int> = ThrowingContext()
    println(throwing.intercepted() === throwing)
    val completion = Continuation<Int>(EmptyCoroutineContext) { result ->
        println(result.getOrThrow())
    }
    println(completion.intercepted() === completion)
    val pending = (::value).createCoroutineUnintercepted(completion)
    println(pending.intercepted() === pending)
    println(pending.intercepted() === pending.intercepted())
    pending.intercepted().resume(Unit)
}
