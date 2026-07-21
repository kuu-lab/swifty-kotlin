// SKIP-DIFF (DEBT-DIFF-003): `CoroutineStart.LAZY` / `launch(start = ...)` is
// intentionally not registered (see HeaderHelpers+SyntheticCoroutineRegistry.swift,
// STDLIB-CORO-072 note): rewriteLauncherCall's dispatcher-aware path treats
// ANY 2-arg launch call's first argument as a CoroutineDispatcher, so a
// CoroutineStart value there crashes at runtime instead of compiling. Needs
// (1) lowering-side disambiguation of the 2nd launch argument by type, and
// (2) a real "pending, not yet started" RuntimeJobHandle state that
// cancel()/start()/join() honor before the body ever runs (same gap behind
// the extra "cancelled cleanly" line in coroutine_exception_handling.kt).
import kotlinx.coroutines.*

// TEST-CORO-003: Coroutine edge cases — empty scope, immediate cancellation,
// yield behaviour, and nested runBlocking equivalents.

fun main() = runBlocking {
    // 1. Empty coroutineScope completes immediately
    coroutineScope { }
    println("empty scope ok")

    // 2. Job that is cancelled before it starts running
    val job = launch(start = CoroutineStart.LAZY) {
        println("should not print")
    }
    job.cancel()
    job.join()
    println("lazy-cancelled: ${job.isCancelled}")

    // 3. yield() gives other coroutines a chance to run
    val order = mutableListOf<Int>()
    launch {
        order.add(1)
        yield()
        order.add(3)
    }
    launch {
        order.add(2)
        yield()
        order.add(4)
    }
    yield()
    yield()
    println("order ok: ${order.size == 4}")

    // 4. Nested async — result is available after await
    val nested = async {
        async { 21 }.await() * 2
    }
    println("nested: ${nested.await()}")

    // 5. isActive check inside coroutine
    var sawActive = false
    val checker = launch {
        sawActive = isActive
    }
    checker.join()
    println("wasActive: $sawActive")

    println("done")
}
