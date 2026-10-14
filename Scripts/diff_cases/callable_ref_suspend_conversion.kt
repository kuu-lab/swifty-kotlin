import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine

// KUU-2123: direct callable references adapt to suspend function parameters.
private var result = ""

private fun runSuspend(block: suspend () -> Unit) {
    block.startCoroutine(Continuation(EmptyCoroutineContext) { it.getOrThrow() })
}

private fun appendUnit() {
    result += "unit"
}

private fun appendString(): String {
    result += "string"
    return "ignored"
}

fun main() {
    runSuspend(::appendUnit)
    runSuspend(::appendString)
    println(result)
}
