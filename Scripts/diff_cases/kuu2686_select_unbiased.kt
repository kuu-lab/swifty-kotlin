// KUU-2686: selectUnbiased must compile and run end-to-end. Fairness itself
// is nondeterministic, so the deterministic part pinned here is that one of
// the ready clauses wins — both branches yield the same result.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.selects.*

fun main() = runBlocking {
    val a = Channel<Int>(1)
    val b = Channel<Int>(1)
    a.send(1)
    b.send(2)
    // Both clauses are ready; whichever the unbiased shuffle picks, the
    // selected element is 1 or 2 — collapse the choice for a stable diff.
    val picked = selectUnbiased<Int> { a.onReceive { it }; b.onReceive { it } }
    println(if (picked == 1 || picked == 2) "picked" else "bad:$picked")

    // Only one ready clause: unbiased order cannot change the outcome.
    val c = Channel<Int>(1)
    println(selectUnbiased<String> {
        c.onReceive { "unexpected" }
        onTimeout(1L) { "timeout" }
    })
    println("done")
}
