import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

// TEST-CORO-003: Advanced cancellation — cooperative cancellation via
// isActive / ensureActive, cancellation with cause, and finally blocks.

suspend fun cancellableWork(): String {
    var count = 0
    while (currentCoroutineContext().isActive && count < 5) {
        delay(1)
        count++
    }
    return "done-$count"
}

fun main() = runBlocking {
    // 1. Job cancelled mid-loop via isActive
    val job1 = launch {
        val r = cancellableWork()
        println("work: $r")
    }
    delay(3)
    job1.cancel()
    job1.join()

    // 2. ensureActive throws CancellationException when cancelled
    val job2 = launch {
        repeat(10) {
            ensureActive()
            delay(1)
        }
        println("ensureActive completed")
    }
    job2.cancel()
    job2.join()
    println("job2 cancelled: ${job2.isCancelled}")

    // 3. finally block runs on cancellation
    val job3Entered = Channel<Int>()
    val job3 = launch {
        try {
            job3Entered.send(0)
            delay(Long.MAX_VALUE)
        } finally {
            println("finally ran")
        }
    }
    // Wait until the child has entered its try block before cancelling, so this case
    // compares cleanup semantics instead of depending on a launch scheduling race
    // (a bare delay() does not guarantee the child started).
    job3Entered.receive()
    job3.cancel()
    job3.join()

    // 4. withContext(NonCancellable) protects cleanup
    val job4Entered = Channel<Int>()
    val job4 = launch {
        try {
            job4Entered.send(0)
            delay(Long.MAX_VALUE)
        } finally {
            withContext(NonCancellable) {
                delay(1)
                println("cleanup done")
            }
        }
    }
    // Ensure the child reaches its try/finally before cancelling so the NonCancellable
    // cleanup deterministically runs on both JVM and native.
    job4Entered.receive()
    job4.cancel()
    job4.join()

    println("done")
}
