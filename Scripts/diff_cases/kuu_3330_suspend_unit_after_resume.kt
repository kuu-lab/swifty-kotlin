import kotlin.coroutines.*

private var continuation: Continuation<*>? = null

private suspend fun <T> tx(block: () -> T): T =
    suspendCoroutine { continuation = it; block() }

private object Dummy

private suspend fun suspect() {
    tx { Dummy }
}

fun main() {
    var result: Any? = null
    var done = false
    val completion = Continuation<Unit>(EmptyCoroutineContext) {}
    (suspend { result = suspect(); done = true }).startCoroutine(completion)
    (continuation as? Continuation<Dummy>)?.resume(Dummy)
    println("result=$result done=$done")
}
