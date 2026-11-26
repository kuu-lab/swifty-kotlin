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
    var suspendedCompletions = 0
    (::suspendingValue).startCoroutine(object : Continuation<Int> {
        override val context: CoroutineContext
            get() = EmptyCoroutineContext

        override fun resumeWith(result: Result<Int>) {
            suspendedCompletions += 1
            suspended = result.getOrThrow()
        }
    })
    val suspendedBeforeResume = suspendedCompletions
    stored?.resume(7)
    println(suspended)
    println(suspendedBeforeResume)
    println(suspendedCompletions)

    var immediate = 0
    var immediateCompletions = 0
    (::immediateValue).startCoroutine(object : Continuation<Int> {
        override val context: CoroutineContext
            get() = EmptyCoroutineContext

        override fun resumeWith(result: Result<Int>) {
            immediateCompletions += 1
            immediate = result.getOrThrow()
        }
    })
    println(immediate)
    println(immediateCompletions)

    val markerReference = ::COROUTINE_SUSPENDED
    println(markerReference is KProperty0<*>)

    val marker: Any = COROUTINE_SUSPENDED
    println(marker === COROUTINE_SUSPENDED)
}
