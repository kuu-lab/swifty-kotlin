import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.Continuation
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.intrinsics.createCoroutineUnintercepted
import kotlin.coroutines.intrinsics.intercepted
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn
import kotlin.coroutines.resume

private class TrackingInterceptor : AbstractCoroutineContextElement(ContinuationInterceptor), ContinuationInterceptor {
    var wraps = 0
    var releases = 0

    override fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T> {
        wraps++
        return object : Continuation<T> by continuation {}
    }

    override fun releaseInterceptedContinuation(continuation: Continuation<*>) {
        releases++
    }
}

private suspend fun immediate(): String = "immediate"

fun main() {
    val interceptor = TrackingInterceptor()
    val results = mutableListOf<String>()
    val completion = object : Continuation<String> {
        override val context: CoroutineContext get() = interceptor
        override fun resumeWith(result: Result<String>) { results += result.getOrThrow() }
    }
    var suspended: Continuation<String>? = null
    val block: suspend String.() -> String = {
        val suffix = suspendCoroutineUninterceptedOrReturn<String> { continuation ->
            suspended = continuation
            COROUTINE_SUSPENDED
        }
        this + suffix
    }
    val start = block.createCoroutineUnintercepted("hello", completion)
    check(suspended == null)
    val intercepted = start.intercepted()
    check(intercepted === start.intercepted())
    check(interceptor.wraps == 1)
    intercepted.resume(Unit)
    check(results.isEmpty())
    check(interceptor.releases == 0)
    suspended!!.resume("!")
    check(results == listOf("hello!"))
    check(interceptor.releases == 1)

    val reference = ::immediate
    reference.createCoroutineUnintercepted(completion).intercepted().resume(Unit)
    check(results == listOf("hello!", "immediate"))
    check(interceptor.wraps == 2 && interceptor.releases == 2)
    println("ok")
}
