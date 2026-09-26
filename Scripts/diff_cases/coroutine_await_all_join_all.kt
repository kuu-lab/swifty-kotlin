// NOTE: Requires kotlinx-coroutines on classpath.
// Collection-receiver `awaitAll()` / `joinAll()`: the idiomatic
// "async/launch a list, then await/join the list" pattern. Only the vararg
// `awaitAll(a, b, c)` existed before, which made `list.awaitAll()` an
// ambiguous overload rather than a resolved call, and `joinAll` was absent
// in both forms.
//
// No explicit `Deferred<..>` / `Job` type annotations appear below on purpose:
// the element types are inferred from `async` / `launch`, which keeps the case
// valid for both compilers.
import kotlinx.coroutines.*

suspend fun boom(): Int {
    throw RuntimeException("boom")
}

fun main() = runBlocking {
    // 1. Collection<Deferred<T>>.awaitAll()
    val ds = listOf(async { 1 }, async { 2 }, async { 3 })
    println("awaitAll: ${ds.awaitAll().sum()}")

    // 2. awaitAll on an empty collection (derived, so no type annotation).
    println("awaitAll-empty: ${ds.take(0).awaitAll().size}")

    // 3. Collection<Job>.joinAll()
    var counter = 0
    val js = listOf(
        launch { counter += 1 },
        launch { counter += 10 },
        launch { counter += 100 }
    )
    js.joinAll()
    println("joinAll: $counter")

    // 4. awaitAll fails fast when one element throws. The siblings carry no
    //    `delay`, so the case does not depend on sibling-cancellation timing
    //    differing between the two compilers.
    try {
        coroutineScope {
            listOf(async { 10 }, async { boom() }).awaitAll()
        }
    } catch (e: Throwable) {
        println("awaitAll-throws: ${e.message}")
    }

    // 5. joinAll after the failing scope: the parent is still usable.
    val after = listOf(launch { counter += 1000 })
    after.joinAll()
    println("joinAll-after: $counter")

    println("done")
}
