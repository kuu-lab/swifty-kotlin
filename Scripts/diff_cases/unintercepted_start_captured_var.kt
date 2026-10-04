import kotlin.coroutines.*
import kotlin.coroutines.intrinsics.*

// A suspend lambda that captures mutable locals must receive its closure state when
// started through the unintercepted entry points (and startCoroutine).
fun main() {
    var starts = 0
    var name = "n"
    val completion = Continuation<Int>(EmptyCoroutineContext) { r -> println("done " + r.getOrThrow()) }

    val function: suspend () -> Int = { starts++; name += "!"; starts + name.length }
    println(function.startCoroutineUninterceptedOrReturn(completion))
    println(starts)
    println(name)

    var viaStart = 0
    val started: suspend () -> Int = { viaStart += 5; viaStart }
    started.startCoroutine(completion)
    println(viaStart)

    val plain: suspend () -> Int = { 3 }
    println(plain.startCoroutineUninterceptedOrReturn(completion))
}
