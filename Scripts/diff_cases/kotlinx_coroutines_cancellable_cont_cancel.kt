import kotlinx.coroutines.*

fun main() = runBlocking {
    try {
        suspendCancellableCoroutine<Int> { continuation ->
            continuation.invokeOnCancellation { cause -> println(cause.message) }
            println(continuation.cancel(CancellationException("stop")))
            println(continuation.cancel())
            println(continuation.isActive)
            println(continuation.isCompleted)
            println(continuation.isCancelled)
            continuation.resume(10) { cause -> println("discard: " + cause.message) }
        }
    } catch (e: CancellationException) {
        println("cancelled")
    }
    try {
        suspendCancellableCoroutine<Int> { continuation ->
            continuation.cancel(CancellationException("late"))
            continuation.invokeOnCancellation { cause -> println(cause.message) }
        }
    } catch (e: CancellationException) {
        println("late handler")
    }
    println(suspendCancellableCoroutine<Int> { continuation ->
        continuation.resume(12) { cause -> println("unexpected") }
        println(continuation.cancel())
    })
}
