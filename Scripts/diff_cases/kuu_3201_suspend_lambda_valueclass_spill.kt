// KUU-3201: two structurally similar suspend lambdas each spill a value-class
// local across `suspendCoroutineUninterceptedOrReturn`. The generated coroutine
// classes used to trip the KIR verifier (`expression NNN is read but never
// defined`, unresolved `<suspendCoroutineUninterceptedOrReturn>` callee).
import kotlin.coroutines.*
import kotlin.coroutines.intrinsics.*

private val completion = object : Continuation<Any?> {
    override val context: CoroutineContext = EmptyCoroutineContext
    override fun resumeWith(result: Result<Any?>) { result.getOrThrow() }
}

@JvmInline
value class Offset(val packed: Long)

private suspend fun suspendHere(): String = suspendCoroutineUninterceptedOrReturn { c ->
    c.resume("K")
    COROUTINE_SUSPENDED
}

private fun builder(c: suspend () -> Unit) {
    c.startCoroutine(completion)
}

private var result = ""

fun box(): String {
    builder {
        val a = Offset(7L)
        val s = suspendHere()
        result += "O" + s + a.packed
    }
    builder {
        val b = Offset(9L)
        val s = suspendHere()
        result += "-" + s + b.packed
    }
    if (result != "OK7-K9") return "FAIL: $result"
    return "OK"
}

fun main() {
    println(box())
}
