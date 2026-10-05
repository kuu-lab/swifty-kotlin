import kotlin.coroutines.Continuation
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.intrinsics.createCoroutineUnintercepted
import kotlin.coroutines.intrinsics.intercepted
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking

private class Recorder(private val wrap: Boolean) : ContinuationInterceptor {
    override val key: CoroutineContext.Key<*> = ContinuationInterceptor.Key
    var calls = 0
    var releases = 0
    var resumes = 0
    var last: Continuation<*>? = null
    override fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T> {
        calls++
        if (!wrap) return continuation
        val wrapper = object : Continuation<T> {
            override val context: CoroutineContext = continuation.context
            override fun resumeWith(result: Result<T>) {
                resumes++
                continuation.resumeWith(result)
            }
        }
        last = wrapper
        return wrapper
    }
    override fun releaseInterceptedContinuation(continuation: Continuation<*>) {
        println("release-identity=${continuation === last}")
        releases++
    }
}

private suspend fun answer(): Int = 42
private suspend fun fail(): Int = throw IllegalStateException("body failure")
private var pending: Continuation<Int>? = null
private suspend fun delayed(): Int = suspendCoroutineUninterceptedOrReturn { continuation ->
    pending = continuation
    COROUTINE_SUSPENDED
}

private fun probe(block: suspend () -> Int, wrap: Boolean, failStart: Boolean) {
    val interceptor = Recorder(wrap)
    val completion = Continuation<Int>(interceptor) { result ->
        println("completed-releases=${interceptor.releases}")
        val failure = result.exceptionOrNull()
        if (failure == null) println(result.getOrThrow()) else println(failure.message)
    }
    val coroutine = block.createCoroutineUnintercepted(completion)
    println(coroutine.context === interceptor)
    val first = coroutine.intercepted()
    println(first === coroutine.intercepted())
    println(first === coroutine)
    println(first.intercepted() === first)
    println("calls=${interceptor.calls}")
    if (failStart) first.resumeWithException(IllegalStateException("start failure")) else first.resume(Unit)
    println("resumes=${interceptor.resumes},releases=${interceptor.releases}")
}

fun main() {
    // The original identity-returning reproducer must intercept exactly once.
    probe(::answer, false, false)
    probe(::answer, true, false)
    probe(::fail, true, false)
    probe(::answer, true, true)

    val interceptor = Recorder(true)
    var completed = false
    val completion = Continuation<Int>(interceptor) { result ->
        println("delayed=${result.getOrThrow()},releases=${interceptor.releases}")
        completed = true
    }
    val coroutine = (::delayed).createCoroutineUnintercepted(completion)
    val first = coroutine.intercepted()
    first.resume(Unit)
    println("suspended-releases=${interceptor.releases}")
    println(first === coroutine.intercepted())
    pending!!.resume(73)
    runBlocking {
        while (!completed) delay(1)
    }

    val ordinary = Continuation<Int>(interceptor) {}
    println(ordinary.intercepted() === ordinary)
    println("ordinary-calls=${interceptor.calls}")
}
