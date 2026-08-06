import kotlinx.coroutines.*

fun main() = runBlocking {
    // The inner delay must dwarf the timeout: with a 10ms delay a loaded runner can
    // schedule the block late enough that even kotlinc completes it before observing
    // the 1ms deadline, printing `1` instead of `null`.
    val timeoutResult = withTimeoutOrNull(1L) {
        delay(1000)
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
