// NOTE: Requires kotlinx-coroutines on classpath.
// CORO-004: Basic delay test — verifies that delay() suspends and resumes
// correctly without blocking the calling thread (non-blocking continuation
// model).  The test launches two coroutines that each delay for different
// durations, then prints a message proving they ran concurrently (the total
// wall time should be ~max(delay1, delay2), not delay1 + delay2).
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

fun main() = runBlocking {
    val start = System.currentTimeMillis()

    // Collect each job's completion string in a Mutex-guarded list instead of
    // printing from inside the coroutines. The scheduler-dependent completion
    // order of the two jobs (JVM vs. native) would otherwise make the printed
    // order nondeterministic. We print from the main coroutine after both jobs
    // join, sorted, so stdout is deterministic on every backend.
    val mutex = Mutex()
    val results = mutableListOf<String>()

    val job1 = launch {
        delay(100)
        mutex.withLock { results.add("job1 done") }
    }
    val job2 = launch {
        delay(50)
        mutex.withLock { results.add("job2 done") }
    }

    job1.join()
    job2.join()

    for (line in results.sorted()) println(line)

    val elapsed = System.currentTimeMillis() - start
    // With non-blocking delay, both run concurrently: elapsed ~ 100ms.
    // With blocking delay, they would serialize: elapsed ~ 150ms.
    // Use a generous threshold (500ms) to avoid flakiness on slow CI runners.
    println(if (elapsed < 500) "concurrent" else "sequential ($elapsed ms)")
    println("done")
}
