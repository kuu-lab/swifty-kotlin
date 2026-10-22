// KUU-2686: when several clauses are ready at once, biased `select` takes
// the first registered clause (upstream semantics) — `selectUnbiased` would
// pick uniformly at random and is not diffable, so only the biased rule is
// pinned here.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.selects.*

fun main() = runBlocking {
    val a = Channel<Int>(1)
    val b = Channel<Int>(1)
    a.send(1)
    b.send(2)
    println(select<String> { a.onReceive { "a:$it" }; b.onReceive { "b:$it" } })
    println(b.receive())

    // Two buffered sends plus a completed deferred: first clause still wins.
    val c = Channel<Int>(1)
    c.send(3)
    val deferred = async { 4 }
    delay(50)
    println(select<String> { c.onReceive { "c:$it" }; deferred.onAwait { "d:$it" }; b.onReceive { "b2:$it" } })
    println(deferred.await())
    b.send(5)
    println(b.receive())
    println("done")
}
