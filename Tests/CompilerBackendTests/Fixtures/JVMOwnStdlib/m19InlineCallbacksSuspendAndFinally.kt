import kotlin.coroutines.*
class Gate {
    var pending: Continuation<String>? = null
    suspend fun await(): String = suspendCoroutine { pending = it }
    fun release(value: String) { pending!!.resume(value) }
}
class Sink: Continuation<String> {
    override val context: CoroutineContext get() = EmptyCoroutineContext
    override fun resumeWith(result: Result<String>) { println(result.getOrThrow()) }
}
suspend fun work(gate: Gate): String = buildString {
    "ab".forEach { append(it); append(gate.await()) }
}
inline fun shadow(action: StringBuilder.() -> Unit): String = buildString {
    if (true) { val action: StringBuilder.() -> Unit = { append("inner") }; this.action() }
    this.action()
}
fun early(): String {
    try { return buildString { "ab".filter { if (it == 'b') return "early"; true }; append("bad") } }
    finally { println("finally") }
}
fun main() {
    println(shadow { append("outer") }); println(early()); val gate = Gate(); val job: suspend () -> String = { work(gate) }
    job.startCoroutine(Sink()); println("pause1"); gate.release("1"); println("pause2"); gate.release("2")
    val action: StringBuilder.() -> Unit = { append("captured") }; println(buildString(action))
    val mapper: (Char) -> Int = { it.code }; println("ab".map(mapper))
    println(buildString { "ab".forEachIndexed { i, c -> append(i); append(c) } })
}
