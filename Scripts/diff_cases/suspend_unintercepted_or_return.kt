// DIFF_JVM
// DIFF_SKIP_NATIVE: JVM-lane regression for suspendCoroutineUninterceptedOrReturn marker access.
import kotlin.coroutines.Continuation
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn
import kotlin.coroutines.resume
import kotlin.coroutines.startCoroutine
import kotlin.reflect.KProperty0

var stored: Continuation<Int>? = null

suspend fun suspendingValue(): Int = suspendCoroutineUninterceptedOrReturn { continuation ->
    stored = continuation
    COROUTINE_SUSPENDED
}

suspend fun immediateValue(): Int = suspendCoroutineUninterceptedOrReturn { 42 }

fun main() {
    var suspended = 0
    (::suspendingValue).startCoroutine(object : Continuation<Int> {
        override val context: CoroutineContext
            get() = EmptyCoroutineContext

        override fun resumeWith(result: Result<Int>) {
            suspended = result.getOrThrow()
        }
    })
    stored?.resume(7)
    println(suspended)

    var immediate = 0
    (::immediateValue).startCoroutine(object : Continuation<Int> {
        override val context: CoroutineContext
            get() = EmptyCoroutineContext

        override fun resumeWith(result: Result<Int>) {
            immediate = result.getOrThrow()
        }
    })
    println(immediate)

    val markerReference = ::COROUTINE_SUSPENDED
    println(markerReference is KProperty0<*>)

    val marker: Any = COROUTINE_SUSPENDED
    println(marker === COROUTINE_SUSPENDED)
}
