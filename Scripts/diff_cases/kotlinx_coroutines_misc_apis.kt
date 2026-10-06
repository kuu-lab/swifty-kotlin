import kotlinx.coroutines.*
import kotlinx.coroutines.InternalCoroutinesApi

// KSP-1568: CoroutineStart.isLazy, CoroutineId, Job.cancelAndJoin,
// joinAll/awaitAll parameter forms, yield(), and Deferred.await — all
// deterministic outputs.

@OptIn(ExperimentalCoroutinesApi::class, InternalCoroutinesApi::class)
fun main() = runBlocking {
    // CoroutineStart.isLazy is true only for LAZY.
    println("lazy=${CoroutineStart.LAZY.isLazy}")
    println("default=${CoroutineStart.DEFAULT.isLazy}")
    println("atomic=${CoroutineStart.ATOMIC.isLazy}")
    println("undispatched=${CoroutineStart.UNDISPATCHED.isLazy}")

    // CoroutineId element: resolved statically in our bundled stdlib; real
    // kotlinc keeps it internal so it can't appear in a diff case.

    // joinAll(vararg) joins every job before returning. The Collection
    // overload exists in the bundled stdlib too, but its signature can't be
    // expressed identically on both compilers, so the diff case exercises the
    // vararg form.
    val j1 = launch { yield() }
    val j2 = launch { yield() }
    joinAll(j1, j2)
    println("joinAllDone")

    // awaitAll(vararg) collects each deferred result in order.
    println("awaitAllVararg=${awaitAll(async { 4 }, async { 5 })}")

    // Deferred.await completes with the async result.
    println("awaited=${async { 9 }.await()}")

    // cancelAndJoin cancels then suspends until the job finishes.
    val cancelled = launch { delay(Long.MAX_VALUE) }
    cancelled.cancelAndJoin()
    println("cancelJoined=${cancelled.isCancelled}")

    // yield() reschedules deterministically; runBlocking waits without a join.
    launch {
        println("child-1")
        yield()
        println("child-2")
    }
    yield()
    println("parent")
}
