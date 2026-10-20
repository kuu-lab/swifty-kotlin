import kotlin.coroutines.*
class Gate {
    var pending: Continuation<Int>? = null
    suspend fun await(): Int = suspendCoroutine { pending = it }
    fun release(n: Int) { pending!!.resume(n) }
}
inline suspend fun <reified T> checked(v: T, gate: Gate): Boolean { gate.await(); return v is T }
inline fun <reified U> reference(): suspend (U, Gate) -> Boolean = ::checked
interface Probe { suspend fun test(v: Any?, gate: Gate): Boolean }
inline fun <reified T> probe(): Probe = object: Probe {
    override suspend fun test(v: Any?, gate: Gate): Boolean { gate.await(); return v is T }
}
fun main() {
    val gate = Gate()
    val work: suspend () -> Boolean = {
        val f: suspend (String, Gate) -> Boolean = ::checked
        println(f("yes", gate)); println(reference<String?>()(null, gate))
        probe<Int>().test(1, gate)
    }
    work.startCoroutine(object: Continuation<Boolean> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<Boolean>) { println(result.getOrThrow()) }
    })
    println("paused"); gate.release(1); gate.release(2); gate.release(3)
}
