import kotlin.coroutines.*
import kotlin.coroutines.intrinsics.*

// KUU-3833: a resume delivered through suspendCoroutineUninterceptedOrReturn's
// block-scoped continuation must reach the completion continuation's resumeWith
// while the suspend call still reports COROUTINE_SUSPENDED — not fold into a
// synchronous return of the delivered value.

private var delivered: String? = null

private suspend fun suspendHere(): String = suspendCoroutineUninterceptedOrReturn { x ->
    x.resume("OK")
    COROUTINE_SUSPENDED
}

private suspend fun suspendWithSuffix(): String {
    val t = suspendCoroutineUninterceptedOrReturn<String> { x ->
        x.resume("A")
        COROUTINE_SUSPENDED
    }
    return (t as String) + "-suffix"
}

private suspend fun suspendFailing(): String = suspendCoroutineUninterceptedOrReturn { x ->
    x.resumeWithException(IllegalStateException("boom"))
    COROUTINE_SUSPENDED
}

private var stored: Continuation<String>? = null
private suspend fun suspendStoring(): String = suspendCoroutineUninterceptedOrReturn { x ->
    stored = x
    COROUTINE_SUSPENDED
}

private suspend fun suspendInside(): String = suspendCoroutineUninterceptedOrReturn { x ->
    x.resume("IN")
    COROUTINE_SUSPENDED
}

private suspend fun suspendDeep(): String {
    val inner = suspendInside()
    return (inner as String) + "-deep"
}

fun main() {
    val completion = object : Continuation<String> {
        override val context: CoroutineContext get() = EmptyCoroutineContext
        override fun resumeWith(value: Result<String>) {
            val failure = value.exceptionOrNull()
            delivered = if (failure == null) "value:${value.getOrThrow()}" else "error:${failure.message}"
        }
    }

    val first: suspend () -> String = { suspendHere() }
    val r1 = first.startCoroutineUninterceptedOrReturn(completion)
    println("r1=${r1 == COROUTINE_SUSPENDED} delivered=$delivered")

    delivered = null
    val second: suspend () -> String = { suspendWithSuffix() }
    val r2 = second.startCoroutineUninterceptedOrReturn(completion)
    println("r2=${r2 == COROUTINE_SUSPENDED} delivered=$delivered")

    delivered = null
    val third: suspend () -> String = { suspendFailing() }
    val r3 = third.startCoroutineUninterceptedOrReturn(completion)
    println("r3=${r3 == COROUTINE_SUSPENDED} delivered=$delivered")

    delivered = null
    val fourth: suspend () -> String = { suspendStoring() }
    val r4 = fourth.startCoroutineUninterceptedOrReturn(completion)
    println("r4=${r4 == COROUTINE_SUSPENDED} delivered=$delivered")
    stored!!.resume("LATE")
    println("after-stored delivered=$delivered")

    delivered = null
    val fifth: suspend () -> String = { suspendDeep() }
    val r5 = fifth.startCoroutineUninterceptedOrReturn(completion)
    println("r5=${r5 == COROUTINE_SUSPENDED} delivered=$delivered")
}
