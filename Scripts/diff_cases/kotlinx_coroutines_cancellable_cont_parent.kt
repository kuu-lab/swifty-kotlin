import kotlinx.coroutines.*
import kotlin.coroutines.resume

fun main() = runBlocking {
    var saved: CancellableContinuation<Int>? = null
    val resumed = launch {
        val value = suspendCancellableCoroutine<Int> { saved = it }
        println(value)
    }
    yield()
    saved?.resume(31)
    resumed.join()
    val cancelled = launch {
        try {
            suspendCancellableCoroutine<Int> { continuation ->
                continuation.invokeOnCancellation { println("parent handler") }
            }
        } catch (e: CancellationException) {
            println("parent cancelled")
        }
    }
    yield()
    cancelled.cancel()
    cancelled.join()
    val prompt = launch {
        try {
            suspendCancellableCoroutine<Int> { continuation ->
                saved = continuation
                continuation.invokeOnCancellation { println("prompt handler") }
            }
            println("unexpected value")
        } catch (e: CancellationException) {
            println("prompt cancelled")
        }
    }
    yield()
    saved?.resume(32) { cause -> println("prompt discard") }
    prompt.cancel()
    prompt.join()
}
