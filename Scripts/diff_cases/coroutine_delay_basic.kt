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

    // Completion order proves concurrency without depending on wall time:
    // with a non-blocking delay the shorter job (job2, 50ms) finishes first,
    // whereas a blocking delay would serialize them in launch order.
    println(if (results.first() == "job2 done") "concurrent" else "sequential")
    println("done")
}
