import kotlinx.coroutines.*

// TEST-CORO-003: Deferred values — async/await, multiple awaiters, and
// combining results from parallel async operations.
//
// CoroutineStart.LAZY is intentionally not covered here: KSwiftK doesn't yet
// have a genuine "pending, not yet started" Job state, the same gap that
// blocks `launch(start = CoroutineStart.LAZY)` (see coroutine_edge_cases.kt
// and docs/diff-skip-inventory.md's structured concurrency / Deferred /
// Supervisor notes).

suspend fun heavyComputation(n: Int): Int {
    delay(1)
    return n * n
}

fun main() = runBlocking {
    // 1. Basic async/await
    val d1 = async { heavyComputation(4) }
    println("deferred: ${d1.await()}")

    // 2. Multiple async in parallel
    val jobs = (1..5).map { n -> async { heavyComputation(n) } }
    val results = jobs.map { it.await() }
    println("results: ${results.sum()}")

    // 3. await on already-completed deferred returns immediately
    val eager = async { 99 }
    eager.await() // ensure completed
    println("re-await: ${eager.await()}")

    // 4. awaitAll shorthand
    val all = awaitAll(
        async { "a" },
        async { "b" },
        async { "c" }
    )
    println("awaitAll: ${all.joinToString(",")}")

    println("done")
}
