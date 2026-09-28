import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.intrinsics.createCoroutineUnintercepted
import kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn

fun main() {
    var starts = 0
    var completed = 0
    val completion = Continuation<Int>(EmptyCoroutineContext) { result ->
        completed = result.getOrThrow()
    }
    val function: suspend () -> Int = {
        starts++
        7
    }
    val pending = function.createCoroutineUnintercepted(completion)
    println(starts)
    pending.resume(Unit)
    println("$starts:$completed")
    println(function.startCoroutineUninterceptedOrReturn(completion))
    println(starts)
}
