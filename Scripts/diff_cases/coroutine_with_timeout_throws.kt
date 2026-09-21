import kotlinx.coroutines.*

// An expired `withTimeout` deadline throws a catchable
// `TimeoutCancellationException`, a subclass of `CancellationException`.
// The timeouts stay far below the blocks' delays so a loaded runner cannot
// complete a block before its deadline (see coroutine_cancellation_edge_cases.kt).
fun main() = runBlocking {
    try {
        withTimeout(10) { delay(1000) }
        println("unexpected-complete")
    } catch (e: TimeoutCancellationException) {
        println("caught: timeout")
        println(e.message)
    }

    // A timeout is a CancellationException, so the supertype clause catches it too.
    try {
        withTimeout(10) { delay(1000) }
        println("unexpected-complete")
    } catch (e: CancellationException) {
        println("caught: cancellation")
    }

    // The non-throwing form still reports expiry as null rather than throwing.
    println(withTimeoutOrNull(10) { delay(1000); 1 })

    // ...and still returns the block's value when it completes in time.
    println(withTimeoutOrNull(5000) { 7 })

    // The reverse relation must NOT hold: a plain cancellation is not a timeout.
    val job = launch {
        try {
            delay(1000)
            println("unexpected-complete")
        } catch (e: TimeoutCancellationException) {
            println("wrong: timeout clause")
        } catch (e: CancellationException) {
            println("caught: plain cancel")
        }
    }
    // Let the child reach its delay() before cancelling: cancelling a
    // not-yet-started coroutine never runs the body, so the catch clauses
    // would not be exercised at all.
    delay(50)
    job.cancel()
    job.join()

    // Reached only if the timeout threw to the caller without cancelling it.
    println("done")
}
