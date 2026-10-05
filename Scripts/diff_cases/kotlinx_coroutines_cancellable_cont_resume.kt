import kotlinx.coroutines.*
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

suspend fun value(): Int = suspendCancellableCoroutine<Int> { continuation ->
    println(continuation.isActive)
    println(continuation.isCompleted)
    continuation.resume(42)
    println(continuation.isCompleted)
    println(continuation.isCancelled)
}

fun main() = runBlocking {
    println(value())
    println(suspendCancellableCoroutine<String?> { it.resume(null) })
    try {
        suspendCancellableCoroutine<Int> { it.resumeWithException(IllegalStateException("boom")) }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    println(suspendCancellableCoroutine<Int> { it.resumeWith(Result.success(7)) })
    println(suspendCancellableCoroutine<Int> { continuation ->
        continuation.resume(8)
        try {
            continuation.resume(9)
        } catch (e: IllegalStateException) {
            println("double resume")
        }
    })
}
