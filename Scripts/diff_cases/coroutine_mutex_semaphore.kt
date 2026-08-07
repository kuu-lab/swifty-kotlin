// SKIP-DIFF (DEBT-DIFF-003): the Sema overload-resolution failure (KSWIFTK-SEMA-0002) on
// Mutex.withLock / Semaphore.withPermit was fixed in KSP-677 (generic-lambda return-type
// inference), and the coroutine-lowering feature gap KSWIFTK-CORO-0003 (capturing suspend
// lambdas launched via launch { } / launch(dispatcher) { } / CoroutineScope.launch { })
// was fixed in BUG-049 -- see the focused, deterministic regression in
// Scripts/diff_cases/coroutine_launch_capture.kt. This broader case still stays skipped
// because it fans out 100+ coroutines on Dispatchers.Default, which exposes a separate,
// pre-existing runtime GC-under-parallelism crash (SIGSEGV in swift_retain when many
// worker threads allocate/retain shared objects at once) that is independent of capture
// forwarding, plus the `delay` runtime dependency inside a non-suspend permit block. See
// docs/diff-skip-inventory.md and BUG-049.
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.*
import java.util.concurrent.atomic.AtomicInteger

// TEST-CORO-003: Mutex and Semaphore — protecting shared state in coroutines,
// withLock helper, and Semaphore for limiting concurrent access.

fun main() = runBlocking {
    // 1. Mutex protects shared counter
    val mutex = Mutex()
    var counter = 0
    val jobs = (1..100).map {
        launch(Dispatchers.Default) {
            mutex.withLock {
                counter++
            }
        }
    }
    jobs.forEach { it.join() }
    println("counter: $counter")

    // 2. Mutex.withLock returns value of block
    val result = mutex.withLock { "locked result" }
    println("result: $result")

    // 3. Mutex is not held after withLock
    println("isLocked: ${mutex.isLocked}")

    // 4. Semaphore limits concurrency
    // Use AtomicInteger to avoid data races when multiple coroutines on
    // Dispatchers.Default update current/maxConcurrent simultaneously.
    val semaphore = Semaphore(3)
    val maxConcurrent = AtomicInteger(0)
    val current = AtomicInteger(0)
    val semJobs = (1..10).map {
        launch(Dispatchers.Default) {
            semaphore.withPermit {
                val c = current.incrementAndGet()
                maxConcurrent.updateAndGet { max -> if (c > max) c else max }
                delay(1)
                current.decrementAndGet()
            }
        }
    }
    semJobs.forEach { it.join() }
    println("max concurrent <= 3: ${maxConcurrent.get() <= 3}")

    // 5. Semaphore with 1 permit acts like a mutex
    val binarySema = Semaphore(1)
    var shared = 0
    val semaJobs = (1..50).map {
        launch(Dispatchers.Default) {
            binarySema.withPermit { shared++ }
        }
    }
    semaJobs.forEach { it.join() }
    println("binary sema shared: $shared")

    println("done")
}
