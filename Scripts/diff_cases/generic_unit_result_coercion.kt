import kotlin.coroutines.*

private var saved: Continuation<*>? = null
private object Dummy
private suspend fun <T> tx(block: () -> T): T = suspendCoroutine { saved = it; block() }
private suspend fun suspect() { tx { Dummy } }

@Suppress("UNCHECKED_CAST")
private fun <T> evil(): T = 42 as T

fun main() {
    var result: Any? = null
    var done = false
    val completion = Continuation<Unit>(EmptyCoroutineContext) { value ->
        println("completion=" + (value.exceptionOrNull()?.toString() ?: "ok"))
    }
    (suspend { result = suspect(); done = true }).startCoroutine(completion)
    println("before=$done")
    (saved as? Continuation<Dummy>)?.resume(Dummy)
    println("result=$result done=$done")

    try { val value: Unit = evil<Unit>(); println("used=$value") }
    catch (e: ClassCastException) { println("used=cast") }
    try { evil<Unit>(); println("discarded=ok") }
    catch (e: ClassCastException) { println("discarded=cast") }
    try { val value: String = evil<String>(); println(value) }
    catch (e: ClassCastException) { println("string=cast") }
    try { println(evil<Any>() as Unit) }
    catch (e: ClassCastException) { println("explicit=cast") }
}
