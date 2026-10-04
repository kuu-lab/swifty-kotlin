// KSP-1154: unintercepted coroutine intrinsics on suspend extension functions.
import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.intrinsics.createCoroutineUnintercepted
import kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn
import kotlin.coroutines.resume

fun main() {
    val completion = Continuation<Int>(EmptyCoroutineContext) { result: Result<Int> ->
        println("completed:${result.getOrThrow()}")
    }
    val block: suspend String.() -> Int = { length + 1 }
    println(block.startCoroutineUninterceptedOrReturn("abc", completion))
    val continuation = block.createCoroutineUnintercepted("abcd", completion)
    continuation.resume(Unit)
}
