import kotlin.coroutines.*
@JvmInline value class Text(val value: String)
inline fun <reified T> identity(v: T): T = v
inline suspend fun <reified T> suspended(v: T): T = v
fun main() {
    val f: suspend (Int) -> Int = ::identity
    println(f is kotlin.reflect.KFunction<*>)
    val g: suspend (Text) -> Text = ::suspended
    val work: suspend () -> Int = { println(g(Text("value")).value); f(42) }
    work.startCoroutine(object: Continuation<Int> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
    })
}
