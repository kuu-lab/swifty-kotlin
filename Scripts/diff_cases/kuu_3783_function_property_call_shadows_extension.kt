import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.startCoroutine
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

// KUU-3783: calling a function-typed property whose name collides with an
// imported extension (`Continuation.resume` ships in the default
// kotlin.coroutines import set) must resolve through the property's
// implicit `invoke`, not report "no viable overload". Mirrors the upstream
// rethrow-in-finally-with-suspension scenario: the exception raised inside
// a `finally` that also suspends must replace the delivered failure.

private var resume: () -> Unit = {}

private suspend fun suspendHere(): String = suspendCoroutineUninterceptedOrReturn { cont ->
    resume = {
        cont.resumeWithException(RuntimeException("Do not catch me"))
    }
    COROUTINE_SUSPENDED
}

private open class EmptyContinuation(
    override val context: kotlin.coroutines.CoroutineContext = EmptyCoroutineContext
) : Continuation<Any?> {
    companion object : EmptyContinuation()
    override fun resumeWith(result: Result<Any?>) {
        result.getOrThrow()
    }
}

private fun builder(c: suspend () -> Unit) {
    c.startCoroutine(EmptyContinuation)
}

private fun box(): String {
    var result = ""
    var count = 0
    try {
        builder {
            try {
                suspendHere()
                count = 1
            } finally {
                if (count == 0) {
                    count = 2
                    result = "O"
                    throw Exception("K")
                } else if (count == 2) {
                    result = "FAIL: execution gets into infinite loop"
                } else {
                    result = "FAIL: exception has not been thrown"
                }
            }
        }
        resume()
    } catch (x: Exception) {
        result += x.message
    }
    return result
}

fun main() {
    println(box())
}
