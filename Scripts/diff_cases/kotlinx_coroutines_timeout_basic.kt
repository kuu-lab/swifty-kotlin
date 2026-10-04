import kotlinx.coroutines.*
import kotlin.time.Duration.Companion.milliseconds

// `withTimeout` returns the block's value when it completes in time (Int,
// Long and Duration deadlines) and throws TimeoutCancellationException —
// a CancellationException subclass — when the deadline expires first.
fun main() = runBlocking {
    println(withTimeout(5000) { 42 })
    println(withTimeout(5000L) { "long-deadline" })
    println(withTimeout(5000.milliseconds) { "duration-deadline" })

    try {
        withTimeout(10.milliseconds) { delay(1000) }
        println("unexpected-complete")
    } catch (e: TimeoutCancellationException) {
        println("caught: timeout")
    }

    // The expiry exception is a CancellationException too.
    try {
        withTimeout(10) { delay(1000) }
        println("unexpected-complete")
    } catch (e: CancellationException) {
        println("caught: cancellation")
    }

    println("done")
}
