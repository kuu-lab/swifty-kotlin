import kotlinx.coroutines.*
import kotlin.time.Duration.Companion.milliseconds

fun main() = runBlocking {
    val failure = IllegalStateException("boom")
    try {
        withTimeout(5000) { throw failure }
        println("unexpected: timeout completed")
    } catch (e: IllegalStateException) {
        println("timeout: ${e === failure}:${e.message}")
    }
    try {
        withTimeoutOrNull(5000) { throw failure }
        println("unexpected: orNull completed")
    } catch (e: IllegalStateException) {
        println("orNull: ${e === failure}:${e.message}")
    }

    try {
        withTimeout(5000L) { delay(1); throw failure }
        println("unexpected: suspended timeout completed")
    } catch (e: IllegalStateException) {
        println("suspended timeout: ${e === failure}:${e.message}")
    }
    try {
        withTimeoutOrNull(5000.milliseconds) { delay(1); throw failure }
        println("unexpected: suspended orNull completed")
    } catch (e: IllegalStateException) {
        println("suspended orNull: ${e === failure}:${e.message}")
    }

    val block: suspend CoroutineScope.() -> Int = { delay(1); throw failure }
    try {
        withTimeout(5000.milliseconds, block)
        println("unexpected: stored timeout completed")
    } catch (e: IllegalStateException) {
        println("stored timeout: ${e === failure}")
    }
    try {
        withTimeoutOrNull(5000L, block)
        println("unexpected: stored orNull completed")
    } catch (e: IllegalStateException) {
        println("stored orNull: ${e === failure}")
    }

    val cancellation = CancellationException("cancelled")
    try {
        withTimeout(5000) { throw cancellation }
        println("unexpected: cancellation dropped")
    } catch (e: CancellationException) {
        println("timeout cancellation: ${e === cancellation}")
    }
    try {
        withTimeoutOrNull(5000) { throw cancellation }
        println("unexpected: cancellation swallowed")
    } catch (e: CancellationException) {
        println("orNull cancellation: ${e === cancellation}")
    }

    try {
        withTimeout(5000) { withTimeout(10) { delay(1000) } }
        println("unexpected: nested timeout completed")
    } catch (e: TimeoutCancellationException) {
        println("nested timeout: ${e.message}")
    }
    try {
        withTimeoutOrNull(5000) { withTimeout(10) { delay(1000) } }
        println("unexpected: nested orNull completed")
    } catch (e: TimeoutCancellationException) {
        println("nested orNull: ${e.message}")
    }
    println(withTimeout(5000) { withTimeoutOrNull(10) { delay(1000); 1 } })
    println(withTimeoutOrNull(5000) { withTimeoutOrNull(10) { delay(1000); 1 } })
    println(withTimeoutOrNull(10) { delay(1000); 1 })
    println(withTimeout(5000) { try { throw failure } catch (e: IllegalStateException) { 42 } })
    println(withTimeoutOrNull(5000) { 0 })
    delay(1)
    println("done")
}
