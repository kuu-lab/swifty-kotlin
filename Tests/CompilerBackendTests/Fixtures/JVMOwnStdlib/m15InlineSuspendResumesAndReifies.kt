import kotlin.coroutines.*
class Gate {
    var pending: Continuation<Int>? = null
    suspend fun await(): Int = suspendCoroutine { pending = it }
    fun release(n: Int) { pending!!.resume(n) }
}
class Sink: Continuation<Int> {
    override val context: CoroutineContext get() = EmptyCoroutineContext
    override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
}
inline suspend fun guarded(block: () -> Int): Int { try { return block() } finally { println("guard") } }
inline suspend fun <reified T> check(value: Any?, block: () -> Int): Int {
    val result = block(); return if (value is T) result else 0
}
suspend fun early(): Int { guarded { return 7 }; return 0 }
fun main() {
    val gate = Gate()
    val work: suspend () -> Int = { println(early()); check<String>("yes") { guarded { gate.await() } } }
    work.startCoroutine(Sink()); println("paused"); gate.release(42)
}
