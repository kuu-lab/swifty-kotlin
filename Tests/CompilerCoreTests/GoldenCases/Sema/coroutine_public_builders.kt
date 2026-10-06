import kotlin.coroutines.*

fun prepare(block: suspend () -> Int, completion: Continuation<Int>): Continuation<Unit> =
    block.createCoroutine(completion)
fun prepareReceiver(block: suspend String.() -> Int, completion: Continuation<Int>): Continuation<Unit> =
    block.createCoroutine("abc", completion)
fun start(block: suspend () -> Int, completion: Continuation<Int>) = block.startCoroutine(completion)
fun startReceiver(block: suspend String.() -> Int, completion: Continuation<Int>) =
    block.startCoroutine("abc", completion)
suspend fun value(): Int = suspendCoroutine<Int> { continuation -> continuation.resume(42) }
