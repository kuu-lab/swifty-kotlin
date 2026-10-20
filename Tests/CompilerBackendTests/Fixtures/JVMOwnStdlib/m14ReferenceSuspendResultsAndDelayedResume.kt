import kotlin.coroutines.*
@JvmInline value class Text(val value: String)
@JvmInline value class Maybe(val value: String?)
@JvmInline value class ArrayValue(val value: IntArray)
@JvmInline value class Box<T>(val value: T)
class Gate {
    var pending: Continuation<Text>? = null
    suspend fun await(v: Text = Text("default")): Text = suspendCoroutine { pending = it }
    fun release(v: Text) { pending!!.resume(v) }
    fun reject() { pending!!.resumeWithException(IllegalStateException("failed")) }
}
class Sink: Continuation<Text> {
    override val context: CoroutineContext get() = EmptyCoroutineContext
    override fun resumeWith(result: Result<Text>) { println(result.getOrThrow()) }
}
suspend fun immediate(v: Text): Text = suspendCoroutine { it.resume(v) }
suspend fun make(): Text = Text("made")
suspend fun fromInt(n: Int = 1): Text = Text("number")
suspend fun optional(v: Text? = null): Text? = v
suspend fun maybe(v: Maybe = Maybe(null)): Maybe = v
suspend fun array(v: ArrayValue = ArrayValue(intArrayOf(1, 2))): ArrayValue = v
suspend fun boxed(v: Maybe?): Maybe? = v
suspend fun <T> generic(v: Box<T>): Box<T> = v
fun main() {
    val gate = Gate()
    val work: suspend () -> Text = {
        var n = 20L
        val first = immediate(Text("sync")); println(first)
        val ref: suspend (Text) -> Text = ::immediate; println(ref(Text("reference")))
        println(make()); println(fromInt())
        println(optional()); println(optional(Text("some"))); println(maybe()); println(boxed(Maybe(null))); println(array())
        println(generic(Box(42))); println(generic(Box<String?>(null)))
        val deferred: suspend (Text) -> Text = gate::await
        val value = deferred(Text("ignored")); n += 2L; println(n); println(value)
        try { gate.await(Text("failure")) } catch (e: IllegalStateException) { println(e.message) }
        finally { println("finally") }
        Text("done")
    }
    work.startCoroutine(Sink()); println("paused"); gate.release(Text("resumed")); println("paused again"); gate.reject()
}
