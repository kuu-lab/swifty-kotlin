import kotlinx.coroutines.*

fun main() = runBlocking {
    var saved: CancellableContinuation<Int>? = null
    val job = launch {
        suspendCancellableCoroutine<Int> { saved = it }
    }
    yield()
    println("registered=${saved != null}")
    job.cancelAndJoin()
}
