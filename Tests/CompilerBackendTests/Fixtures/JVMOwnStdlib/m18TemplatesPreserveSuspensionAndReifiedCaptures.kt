import kotlin.coroutines.*
class Text(val n: Int) {
    override fun toString(): String { println("str$n"); return "T$n" }
}
fun make(n: Int): Text { println("arg$n"); return Text(n) }
class Gate {
    var pending: Continuation<Text>? = null
    suspend fun await(): Text = suspendCoroutine { pending = it }
    fun release() { pending!!.resume(Text(2)) }
}
inline fun <reified T> renderer(): (Any?) -> String = { "${T::class.simpleName}:${it is T}:$it" }
fun main() {
    val gate = Gate()
    val work: suspend () -> String = { "${make(1)}:${gate.await()}:${make(3)}" }
    work.startCoroutine(object: Continuation<String> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<String>) { println(result.getOrThrow()) }
    })
    println("paused"); gate.release()
    println(renderer<UInt>()(4294967295u))
}
