import kotlin.coroutines.*
class Gate {
    var pending: Continuation<Int>? = null
    suspend fun await(): Int = suspendCoroutine { pending = it }
    fun release(value: Int) { pending!!.resume(value) }
}
class Sink: Continuation<Map<Int, String>> {
    override val context: CoroutineContext get() = EmptyCoroutineContext
    override fun resumeWith(result: Result<Map<Int, String>>) { println(result.getOrThrow()) }
}
suspend fun work(gate: Gate): Map<Int, String> = listOf("a", "b").associate { gate.await() to it }
fun early(): Int { try { listOf(1, 2, 3).groupBy { if (it == 2) return 42; it }; return 0 } finally { println("finally") } }
fun terminal(): Int { sequenceOf(1, 2, 3).forEach { if (it == 2) return 43 }; return 0 }
fun arrayEarly(): Int { intArrayOf(1, 2).associate { if (it == 2) return 44; it to it }; return 0 }
fun main() {
    println(early()); println(terminal()); println(arrayEarly())
    val gate = Gate(); val job: suspend () -> Map<Int, String> = { work(gate) }
    job.startCoroutine(Sink()); println("pause1"); gate.release(7); println("pause2"); gate.release(8)
    var total = 0; val captured = sequenceOf(1, 2).map { total += it; total }
    println(total); println(captured.toList()); println(captured.toList()); println(total)
    val selector: (String) -> Int = { it.length }; println(listOf("a", "bb").groupBy(selector))
}
