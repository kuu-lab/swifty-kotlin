import kotlin.coroutines.*
fun interface AsyncOp { suspend fun apply(value: Int): Int }
suspend fun immediate(value: Int): Int = suspendCoroutine { it.resume(value) }
class Sink : Continuation<Unit> {
    override val context: CoroutineContext get() = EmptyCoroutineContext
    override fun resumeWith(result: Result<Unit>) { result.getOrThrow(); println("complete") }
}
fun main() {
    val operation = AsyncOp { immediate(it * 2) }
    val callback: (Int) -> Int = { it * 2 }
    val adapted = AsyncOp(callback)
    val work: suspend () -> Unit = {
        println(operation.apply(21))
        println(adapted.apply(21))
        suspendCoroutine<Unit> { it.resume(Unit) }
    }
    work.startCoroutine(Sink())
}
