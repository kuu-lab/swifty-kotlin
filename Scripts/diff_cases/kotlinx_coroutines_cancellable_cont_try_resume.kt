import kotlinx.coroutines.*

@OptIn(InternalCoroutinesApi::class)
fun main() = runBlocking {
    println(suspendCancellableCoroutine<Int> { continuation ->
        val key = Any()
        val token = continuation.tryResume(21, key)
        println(token != null)
        println(continuation.tryResume(21, key) === token)
        println(continuation.tryResume(22) == null)
        if (token != null) continuation.completeResume(token)
    })
    try {
        suspendCancellableCoroutine<Int> { continuation ->
            val token = continuation.tryResumeWithException(IllegalArgumentException("failed"))
            if (token != null) continuation.completeResume(token)
        }
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    try {
        suspendCancellableCoroutine<Int> { continuation ->
            continuation.cancel(CancellationException("cancelled"))
            println(continuation.tryResume(5) == null)
        }
    } catch (e: CancellationException) {
        println(e.message)
    }
}
