import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn
import kotlin.coroutines.resume
import kotlin.coroutines.startCoroutine

private var out = ""

private suspend fun swr(value: Boolean): Boolean =
    suspendCoroutineUninterceptedOrReturn { continuation ->
        continuation.resume(value)
        COROUTINE_SUSPENDED
    }

fun main() {
    val job: suspend () -> Unit = {
        if (swr(true)) out = "if-true" else out = "if-false"
        if (swr(false)) out += ":unexpected-if-true" else out += ":if-false"

        var whileCount = 0
        while (swr(whileCount++ < 2)) out += ":while"

        var doWhileCount = 0
        do {
            out += ":do"
            doWhileCount++
        } while (swr(doWhileCount < 2))
    }
    val completion = Continuation<Unit>(EmptyCoroutineContext) { println(out) }
    job.startCoroutine(completion)
}
