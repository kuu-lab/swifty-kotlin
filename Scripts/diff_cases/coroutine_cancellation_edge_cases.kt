// SKIP-DIFF (DEBT-DIFF-003): advanced coroutine/channel/flow parity tracking
import kotlinx.coroutines.*

fun main() = runBlocking {
    val timeoutResult = withTimeoutOrNull(1L) {
        delay(10)
        1
    }
    println(timeoutResult)

    val cancelJob = launch {
        try {
            delay(100)
            println("unexpected-complete")
        } catch (e: CancellationException) {
            println("cancelled")
        }
    }
    cancelJob.cancel()
    cancelJob.join()

    try {
        coroutineScope {
            throw IllegalStateException("boom")
        }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
}
